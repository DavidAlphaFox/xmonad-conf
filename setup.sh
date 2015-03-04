#!/bin/sh

echo Looking for my installation directory...
SCRIPT_HOME=`dirname $0`
SCRIPT_HOME=`realpath "$SCRIPT_HOME"`
XMONAD_HOME=`realpath "$HOME/.xmonad"`
if [ "$SCRIPT_HOME" != "$XMONAD_HOME" ]; then
	echo "The Xmonad project should be placed directly in\
 your $XMONAD_HOME directory."
	echo "Aborting."
	exit 1
fi

if [ -x "$SCRIPT_HOME/setup.sh" ]; then
	echo "Found myself in $SCRIPT_HOME, good."
else
	echo "Hmm, I cannot find my own directory. Giving up..."
	exit 1
fi

SHELL_SETUP="$SCRIPT_HOME/shell-setup/setup.sh"
if [ -x "$SHELL_SETUP" ]; then
	echo "Found submodule shell-setup. Very good."
	$SHELL_SETUP
else
	echo "WARNING: Submodule shell-setup does not exist. Skipping."
fi

echo Checking packages...
pkg info slim sudo gtk2 xterm xscreensaver \
	hs-xmonad hs-network hs-xmonad-contrib \
	firefox gimp libreoffice dmenu gmrun \
	dzen2 weechat-devel zenity claws-mail \
	gtk-oxygen-engine xrdb xsetroot setxkbmap gnupg \
	xmodmap hsetroot \
	> /dev/null
if [ $? -ne 0 ]; then
	echo "ERROR: Missing packages for setup (for X)."
	exit 1
fi

cd $HOME
REMOVE_FILES=".xinitrc .Xdefaults .gtkrc-2.0 \
	.config/gtk-3.0/settings.ini \
	"

for df in $REMOVE_FILES; do
	echo Checking dotfile: $df
	test -e $df && test ! -L $df && \
		echo "*** It is not a soft-link. Please move it to a safe location!" && exit 1
done

# remove old stuff
cd $HOME
echo Removing old softlinks...
rm -f $REMOVE_FILES

# prepare conf in user's home
echo Reinstalling softlinks...
ln -s $SCRIPT_HOME/xsettings/.xinitrc .
ln -s $SCRIPT_HOME/xsettings/.Xdefaults .
ln -s $SCRIPT_HOME/xsettings/.gtkrc-2.0 .

mkdir -p $HOME/.config/gtk-3.0
cd $HOME/.config/gtk-3.0
ln -s $SCRIPT_HOME/xsettings/settings.ini .

cd $HOME
echo Preparing xmonad...
xmonad --recompile

echo "-----------------------------------------------------------------"
echo "DONE!"
echo "-----------------------------------------------------------------"
echo "Don't forget to copy $SCRIPT_HOME/xkb/us_alt"
echo "for keyboard bindings."
echo "Also restart xmonad with:"
echo "xmonad --restart"
echo "-----------------------------------------------------------------"
exit 0