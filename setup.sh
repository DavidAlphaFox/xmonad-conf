#!/bin/sh

checkfont() {
	FNTS=`fc-list "$1"`
	if [ -z "$FNTS" ]; then
		echo "WARNING: $1 is not available."
	fi
}

echo "[Xmonad setup] Looking for my installation directory..."
SCRIPT_HOME=`dirname $0`
SCRIPT_HOME=`readlink -f "$SCRIPT_HOME"`
XMONAD_HOME=`readlink -f "$HOME/.xmonad"`
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

echo "[Xmonad setup] Executing shell-setup first..."

# Execute it first
cd "$SCRIPT_HOME"
SHELLSETUP="./shell-setup/setup.sh"
if [ ! -x "$SHELLSETUP" ]; then
	echo "[Xmonad setup] Don't have submodule, yet. Checking out..."
	git submodule init
	git submodule update
	if [ $? -ne 0 ]; then
		echo "*** FAILED to check out."
		exit 1
	fi
else
	echo "[Xmonad setup] Have submodule. Updating..."
	cd ./shell-setup
	git pull
	if [ $? -ne 0 ]; then
		echo "*** FAILED to update."
		exit 1
	fi
	cd "$SCRIPT_HOME"
fi
$SHELLSETUP
if [ $? -ne 0 ]; then
	echo "Submodule shell-setup failed. Aborting."
	exit 1
fi

echo "[Xmonad setup] Checking fonts..."
checkfont "FontAwesome"
checkfont "Fantasque Sans Mono"

OS=`uname -s`
if [ "$OS" = "FreeBSD" ]; then
	echo "[Xmonad setup] Checking packages..."
	pkg info slim sudo gtk2 rxvt-unicode xscreensaver \
		hs-xmonad hs-network hs-xmonad-contrib hs-xmobar \
		hs-bsd-sysctl \
		firefox dmenu gmrun weechat \
		gtk-oxygen-engine xrdb xsetroot setxkbmap gnupg \
		xmodmap hsetroot fira fantasque-sans-mono \
		roboto-fonts-ttf xdotool xfe xwininfo \
		> /dev/null
	if [ $? -ne 0 ]; then
		echo "ERROR: Missing packages for setup (for X)."
		exit 1
	fi
	echo "[Xmonad setup] Checking recommended packages..."
	pkg info gimp libreoffice weechat > /dev/null
	if [ $? -ne 0 ]; then
		echo "WARNING: Some recommended packages are not installed."
	fi
else
	echo "[Xmonad setup] WARNING: Skipped checking packages..."
fi

echo "[Xmonad setup] Checking software capabilities..."
echo "Checking xmonad..."
xmonad --version | egrep -q "xmonad 0.1[12]"
if [ $? -ne 0 ]; then
	echo "*** need Xmonad 0.11 or 0.12."
	exit 1
else
	echo "-> Xmonad is ok, good."
fi

cd $HOME
REMOVE_FILES=".xinitrc .xsession .Xdefaults .gtkrc-2.0 \
	.config/gtk-3.0/settings.ini .config/user-dirs.dirs \
	.vimperatorrc.local .xpdfrc \
	"

for df in $REMOVE_FILES; do
	echo Checking dotfile: $df
	test -e $df && test ! -L $df && \
		echo "*** It is not a soft-link. Please move it to a safe location!" && exit 1
done

# remove old stuff
cd $HOME
echo "[Xmonad setup] Removing old softlinks..."
rm -f $REMOVE_FILES

# prepare conf in user's home
echo "[Xmonad setup] Reinstalling softlinks..."
ln -s $SCRIPT_HOME/xsettings/.xinitrc .
ln -s $SCRIPT_HOME/xsettings/.xinitrc .xsession
ln -s $SCRIPT_HOME/xsettings/.Xdefaults .
ln -s $SCRIPT_HOME/xsettings/.gtkrc-2.0 .
ln -s $SCRIPT_HOME/xsettings/.vimperatorrc.local .
ln -s $SCRIPT_HOME/xsettings/.xpdfrc .

mkdir -p $HOME/.config
cd $HOME/.config
ln -s $SCRIPT_HOME/xsettings/user-dirs.dirs .

mkdir -p $HOME/.config/gtk-3.0
cd $HOME/.config/gtk-3.0
ln -s $SCRIPT_HOME/xsettings/settings.ini .

echo Preparing SysInfoBar...
cd $HOME/.xmonad/lib
ghc --make SysInfoBar.hs
if [ $? -ne 0 ]; then
	echo "*** Building SysInfoBar binary failed"
	exit 1
fi

cd $HOME
echo Preparing xmonad...
xmonad --recompile
if [ $? -ne 0 ]; then
	echo "*** Building xmonad failed"
	exit 1
fi

echo "-----------------------------------------------------------------"
echo "[Xmonad setup] Finished successfully."
echo "-----------------------------------------------------------------"
echo "Don't forget to copy $SCRIPT_HOME/xkb/us_alt"
echo "for keyboard bindings."
echo "Also restart xmonad with:"
echo "xmonad --restart"
echo "-----------------------------------------------------------------"

exit 0
