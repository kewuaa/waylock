WAYLOCK(1) "https://codeberg.org/ifreund/waylock" "General Commands Manual"

# NAME

waylock - a small Wayland screenlocker

# SYNOPSIS

*waylock* [_options_]

# DESCRIPTION

Waylock is a small screenlocker for Wayland compositors implementing
*ext-session-lock-v1*. The *ext-session-lock-v1* protocol is significantly
more robust than previous client-side Wayland screen locking approaches.
Importantly, the screenlocker crashing does not cause the session to be
unlocked.

# OPTIONS

*-h*
	Print a help message and exit.

*-version*
	Print the version number and exit.

*-log-level* [*error*|*warning*|*info*|*debug*]
	Set the log level of waylock. At the *error* log level, only errors
	are logged.  At the *debug* log level, everything is logged including
	verbose debug messages.

*-fork-on-lock*
	Fork to the background after locking the session. This is useful to
	integrate with idle management daemons without racing to lock the
	session before suspend. With this option waylock will exit once the
	session has been locked and it is safe to suspend.

*-ready-fd* _fd_
	Write a newline to file descriptor _fd_ (a number) after locking and
	close the _fd_. This is useful if a fork-less lock notification is needed;
	for example, for integration with a service manager.

# USAGE

Run the waylock executable to lock the session. All monitors will be blanked
with the *-init-color*. Typing causes the color to change to the
*-input-color*. If *-input-alt-color* is set, the typing color will alternate
between this and the former. Esc or Ctrl-U clears all current input, while
backspace deletes the last UTF-8 codepoint.

To unlock the session, type your password and press Enter. If the password
is correct, waylock will unlock the session and exit. Otherwise, the color
will change to the *-fail-color* and you may try again.

In order to automatically run waylock after a certain amount of time with
no input or before sleep, the *swayidle*(1) utility or a similar program
may be used. See the *swayidle*(1) man page for details.

# AUTHORS

Maintained by Isaac Freund <mail@isaacfreund.com> who is assisted by open
source contributors. For more information about waylock's development, see
https://codeberg.org/ifreund/waylock.

# SEE ALSO

*pam*(8), *swayidle*(1)
