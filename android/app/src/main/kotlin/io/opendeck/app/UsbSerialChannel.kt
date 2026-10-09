package io.opendeck.app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * USB serial over Android's USB host API, used to flash the board from a phone.
 * The ESP32-S3 USB-Serial/JTAG port and the OpenDeck firmware's USB port are CDC-ACM;
 * boards without native USB use a WCH CH340 or Silicon Labs CP210x bridge, which
 * take vendor requests instead.
 */
class UsbSerialChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val manager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "opendeck/usb")
    private val events = EventChannel(messenger, "opendeck/usb/data")
    private var sink: EventChannel.EventSink? = null

    private var connection: UsbDeviceConnection? = null
    private var control: UsbInterface? = null
    private var data: UsbInterface? = null
    private var input: UsbEndpoint? = null
    private var output: UsbEndpoint? = null
    private var reader: Thread? = null
    @Volatile private var reading = false
    private var dtr = false
    private var rts = false
    private var kind = Kind.CDC

    private enum class Kind { CDC, CH34X, CP210X }

    private val permissionAction = context.packageName + ".USB_PERMISSION"
    private var pendingOpen: Pair<UsbDevice, (Boolean) -> Unit>? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.action) {
                permissionAction -> {
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val pending = pendingOpen
                    pendingOpen = null
                    pending?.second?.invoke(granted)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device = deviceFrom(intent)
                    if (device != null && connection != null && device.deviceName == openName) {
                        closePort()
                        main.post { sink?.endOfStream() }
                    }
                }
            }
        }
    }
    private var openName: String? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        registerReceiver()
    }

    @SuppressLint("UnspecifiedRegisterReceiverFlag")
    private fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(permissionAction)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    fun dispose() {
        closePort()
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
        }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "list" -> result.success(manager.deviceList.values.map {
                    mapOf(
                        "id" to it.deviceName,
                        "vid" to it.vendorId,
                        "pid" to it.productId,
                        "name" to (it.productName ?: ""),
                    )
                })
                "open" -> open(call.argument<String>("id")!!, call.argument<Int>("baud") ?: 115200, result)
                "write" -> {
                    write(call.argument<ByteArray>("data")!!)
                    result.success(null)
                }
                "signals" -> {
                    call.argument<Boolean>("dtr")?.let { dtr = it }
                    call.argument<Boolean>("rts")?.let { rts = it }
                    setControlLines()
                    result.success(null)
                }
                "baud" -> {
                    setLineCoding(call.argument<Int>("baud")!!)
                    result.success(null)
                }
                "close" -> {
                    closePort()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("usb", e.message ?: e.toString(), null)
        }
    }

    private fun open(id: String, baud: Int, result: MethodChannel.Result) {
        val device = manager.deviceList[id]
        if (device == null) {
            result.error("usb", "The board was unplugged.", null)
            return
        }
        val connect = {
            try {
                connect(device, baud)
                result.success(true)
            } catch (e: Exception) {
                closePort()
                result.error("usb", e.message ?: e.toString(), null)
            }
        }
        if (manager.hasPermission(device)) {
            connect()
            return
        }
        pendingOpen = Pair(device) { granted: Boolean ->
            if (granted) connect() else result.error("usb", "USB permission was denied.", null)
        }
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(permissionAction).setPackage(context.packageName)
        manager.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    private fun connect(device: UsbDevice, baud: Int) {
        closePort()
        kind = when (device.vendorId) {
            0x1A86 -> Kind.CH34X
            0x10C4 -> Kind.CP210X
            else -> Kind.CDC
        }
        var ctrl: UsbInterface? = null
        var dataIface: UsbInterface? = null
        if (kind == Kind.CDC) {
            for (i in 0 until device.interfaceCount) {
                val iface = device.getInterface(i)
                if (iface.interfaceClass == UsbConstants.USB_CLASS_COMM && ctrl == null) ctrl = iface
                if (iface.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA && dataIface == null) dataIface = iface
            }
        } else if (device.interfaceCount > 0) {
            // Bridges have one vendor-specific interface with the bulk endpoints.
            dataIface = device.getInterface(0)
        }
        if (dataIface == null) throw IllegalStateException("This USB device is not a serial port.")
        val conn = manager.openDevice(device) ?: throw IllegalStateException("Could not open the USB device.")
        if (ctrl != null) conn.claimInterface(ctrl, true)
        if (!conn.claimInterface(dataIface, true)) {
            conn.close()
            throw IllegalStateException("The USB port is busy.")
        }
        for (i in 0 until dataIface.endpointCount) {
            val ep = dataIface.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) input = ep else output = ep
        }
        if (input == null || output == null) {
            conn.close()
            throw IllegalStateException("The USB serial port has no data endpoints.")
        }
        connection = conn
        control = ctrl
        data = dataIface
        openName = device.deviceName
        dtr = false
        rts = false
        when (kind) {
            Kind.CH34X -> ch34xInit()
            Kind.CP210X -> cp210xRequest(CP210X_IFC_ENABLE, 1)
            Kind.CDC -> {}
        }
        setLineCoding(baud)
        setControlLines()
        startReader()
    }

    private fun vendorOut(request: Int, value: Int, index: Int) {
        val conn = connection ?: return
        val r = conn.controlTransfer(0x40, request, value, index, null, 0, 1000)
        if (r < 0) throw IllegalStateException("USB serial setup failed (request 0x${request.toString(16)}).")
    }

    private fun vendorIn(request: Int, value: Int, index: Int, length: Int): ByteArray {
        val conn = connection ?: return ByteArray(0)
        val buf = ByteArray(length)
        conn.controlTransfer(0xC0, request, value, index, buf, length, 1000)
        return buf
    }

    // CH340/CH341: the sequence the Linux and usb-serial-for-android drivers use.
    private fun ch34xInit() {
        vendorIn(0x5F, 0, 0, 2)
        vendorOut(0xA1, 0, 0)
        ch34xBaud(115200)
        vendorIn(0x95, 0x2518, 0, 2)
        vendorOut(0x9A, 0x2518, 0x00C3) // 8 data bits, no parity, 1 stop bit, rx and tx on
        vendorIn(0x95, 0x0706, 0, 2)
        vendorOut(0xA1, 0x501F, 0xD90A)
    }

    private fun ch34xBaud(baud: Int) {
        var factor: Long
        var divisor: Int
        if (baud == 921600) {
            divisor = 7
            factor = 0xF300L
        } else {
            factor = 1532620800L / baud
            divisor = 3
            while (factor > 0xFFF0 && divisor > 0) {
                factor = factor shr 3
                divisor--
            }
            if (factor > 0xFFF0) throw IllegalArgumentException("Unsupported baud rate $baud")
            factor = 0x10000L - factor
        }
        divisor = divisor or 0x80 // send right away instead of waiting for a full buffer
        vendorOut(0x9A, 0x1312, (factor and 0xFF00L).toInt() or divisor)
        vendorOut(0x9A, 0x0F2C, (factor and 0xFFL).toInt())
    }

    private fun cp210xRequest(request: Int, value: Int, payload: ByteArray? = null) {
        val conn = connection ?: return
        val r = conn.controlTransfer(0x41, request, value, data?.id ?: 0, payload, payload?.size ?: 0, 1000)
        if (r < 0) throw IllegalStateException("USB serial setup failed (request 0x${request.toString(16)}).")
    }

    private fun startReader() {
        val conn = connection ?: return
        val ep = input ?: return
        reading = true
        reader = Thread {
            val buf = ByteArray(maxOf(ep.maxPacketSize, 64) * 16)
            while (reading) {
                val n = conn.bulkTransfer(ep, buf, buf.size, 100)
                if (n > 0) {
                    val chunk = buf.copyOf(n)
                    main.post { sink?.success(chunk) }
                }
            }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun write(bytes: ByteArray) {
        val conn = connection ?: throw IllegalStateException("Port is not open.")
        val ep = output!!
        var off = 0
        while (off < bytes.size) {
            val len = minOf(bytes.size - off, 16384)
            val chunk = if (off == 0 && len == bytes.size) bytes else bytes.copyOfRange(off, off + len)
            val n = conn.bulkTransfer(ep, chunk, len, 2000)
            if (n <= 0) throw IllegalStateException("USB write failed.")
            off += n
        }
    }

    private fun controlIndex(): Int = (control ?: data)?.id ?: 0

    private fun setControlLines() {
        val conn = connection ?: return
        when (kind) {
            // Active low, as on the chip's pins.
            Kind.CH34X -> vendorOut(0xA4, (if (dtr) 0x20 else 0).or(if (rts) 0x40 else 0).inv() and 0xFF, 0)
            Kind.CP210X -> cp210xRequest(CP210X_SET_MHS, (if (dtr) 1 else 0) or (if (rts) 2 else 0) or 0x0300)
            Kind.CDC -> {
                val value = (if (dtr) 1 else 0) or (if (rts) 2 else 0)
                conn.controlTransfer(0x21, 0x22, value, controlIndex(), null, 0, 1000)
            }
        }
    }

    private fun setLineCoding(baud: Int) {
        val conn = connection ?: return
        if (kind == Kind.CH34X) {
            ch34xBaud(baud)
            return
        }
        if (kind == Kind.CP210X) {
            val b = byteArrayOf(
                (baud and 0xFF).toByte(),
                ((baud shr 8) and 0xFF).toByte(),
                ((baud shr 16) and 0xFF).toByte(),
                ((baud shr 24) and 0xFF).toByte(),
            )
            cp210xRequest(CP210X_SET_LINE_CTL, 0x0800) // 8 data bits, no parity, 1 stop bit
            cp210xRequest(CP210X_SET_BAUDRATE, 0, b)
            return
        }
        val coding = byteArrayOf(
            (baud and 0xFF).toByte(),
            ((baud shr 8) and 0xFF).toByte(),
            ((baud shr 16) and 0xFF).toByte(),
            ((baud shr 24) and 0xFF).toByte(),
            0, // 1 stop bit
            0, // no parity
            8, // data bits
        )
        conn.controlTransfer(0x21, 0x20, 0, controlIndex(), coding, coding.size, 1000)
    }

    private fun closePort() {
        reading = false
        reader?.join(300)
        reader = null
        if (kind == Kind.CP210X && connection != null) {
            try {
                cp210xRequest(CP210X_IFC_ENABLE, 0)
            } catch (_: Exception) {
            }
        }
        val conn = connection
        connection = null
        if (conn != null) {
            control?.let { conn.releaseInterface(it) }
            data?.let { conn.releaseInterface(it) }
            conn.close()
        }
        control = null
        data = null
        input = null
        output = null
        openName = null
    }

    private companion object {
        const val CP210X_IFC_ENABLE = 0x00
        const val CP210X_SET_LINE_CTL = 0x03
        const val CP210X_SET_MHS = 0x07
        const val CP210X_SET_BAUDRATE = 0x1E
    }

    @Suppress("DEPRECATION")
    private fun deviceFrom(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        else intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
}
