Release builds of the app bundle the firmware here (`opendeck-<board>.bin`), so
first-time setup can flash a board without an internet connection. The files
are produced by the firmware workflow and are not checked in. When this folder
has no image, the app downloads it from the latest GitHub release instead.
