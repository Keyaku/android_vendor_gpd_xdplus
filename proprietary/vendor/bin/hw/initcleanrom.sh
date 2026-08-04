#!/system/bin/sh

# ============== GLOBAL ===============

# Create the directory
mkdir /vendor/nvdata/cleanrom

# And make it accessible by everyone
chmod 0777 /vendor/nvdata/cleanrom

# ========= HEADPHONE JACK ============

# We don't have a default headphone jack polarity setting yet
if [ ! -f /vendor/nvdata/cleanrom/headphone_mode ]
then
	# ISPLUGGED should be 0 if the output route has been set to the speaker
	ISPLUGGED=`dumpsys audio | grep mMainType | cut "-dx" -f2`

	# Repeat this until we have a valid value
	while [ "$ISPLUGGED" == "" ]
	do
		# Keep polling
		ISPLUGGED=`dumpsys audio | grep mMainType | cut "-dx" -f2`
	done

	# Check ISPLUGGED
	if [ "$ISPLUGGED" == "0" ]
	then
		# If the speaker route gets picked, we're most likely dealing with a revision 1 unit
		echo 0 > /vendor/nvdata/cleanrom/headphone_mode
	else
		# If the headphone route gets picked, we're most likely dealing with a revision 2+ unit
		echo 1 > /vendor/nvdata/cleanrom/headphone_mode
	fi
fi

# Make the headphone jack polarity setting file writable
chmod 0777 /vendor/nvdata/cleanrom/headphone_mode

# Restore the headphone jack polarity on system restart
cat /vendor/nvdata/cleanrom/headphone_mode > /sys/bus/platform/drivers/Accdet_Driver/set_headset_mode

# =========== GAMEPAD MODE ============

# We don't have a default gamepad mode setting yet
if [ ! -f /vendor/nvdata/cleanrom/gamepad_mode ]
then
	# Let's default to PS3 mode
	echo 0 > /vendor/nvdata/cleanrom/gamepad_mode
fi

# Make the gamepad mode setting file writable
chmod 0777 /vendor/nvdata/cleanrom/gamepad_mode

# Restore the gamepad mode on system restart
cat /vendor/nvdata/cleanrom/gamepad_mode > /sys/devices/soc/soc:joystick@/mode

# ======= SHOULDER BUTTON SWAP ========

# We don't have a shoulder button swap setting yet
if [ ! -f /vendor/nvdata/cleanrom/gamepad_swap_shoulder_button ]
then
	# Let's default to disabled (yes, 1 means disabled in this case)
	echo 1 > /vendor/nvdata/cleanrom/gamepad_swap_shoulder_button
fi

# Make the shoulder button swap setting file writable
chmod 0777 /vendor/nvdata/cleanrom/gamepad_swap_shoulder_button

# Restore the shoulder button swap setting on system restart
cat /vendor/nvdata/cleanrom/gamepad_swap_shoulder_button > /sys/devices/soc/soc:joystick@/exchange

# === LITTLE CORE MINIMUM FREQUENCY ===

# We don't have a default Little Core minimum frequency setting yet
if [ ! -f /vendor/nvdata/cleanrom/little_core_min_frequency ]
then
	# Let's default to 507MHz
	echo 507000 > /vendor/nvdata/cleanrom/little_core_min_frequency
fi

# Make the little core minimum frequency setting file writable
chmod 0777 /vendor/nvdata/cleanrom/little_core_min_frequency

# === LITTLE CORE MAXIMUM FREQUENCY ===

# We don't have a default Little Core maximum frequency setting yet
if [ ! -f /vendor/nvdata/cleanrom/little_core_max_frequency ]
then
	# Let's default to 1703MHz
	echo 1703000 > /vendor/nvdata/cleanrom/little_core_max_frequency
fi

# Make the little core maximum frequency setting file writable
chmod 0777 /vendor/nvdata/cleanrom/little_core_max_frequency

# ==== BIG CORE MINIMUM FREQUENCY =====

# We don't have a default Big Core minimum frequency setting yet
if [ ! -f /vendor/nvdata/cleanrom/big_core_min_frequency ]
then
	# Let's default to 507MHz
	echo 507000 > /vendor/nvdata/cleanrom/big_core_min_frequency
fi

# Make the big core minimum frequency setting file writable
chmod 0777 /vendor/nvdata/cleanrom/big_core_min_frequency

# ==== BIG CORE MAXIMUM FREQUENCY =====

# We don't have a default Big Core maximum frequency setting yet
if [ ! -f /vendor/nvdata/cleanrom/big_core_max_frequency ]
then
        # Let's default to 2106MHz
        echo 2106000 > /vendor/nvdata/cleanrom/big_core_max_frequency
fi

# Make the big core maximum frequency setting file writable
chmod 0777 /vendor/nvdata/cleanrom/big_core_max_frequency

# ========== RECOVERY STUFF ===========
mkdir /cache/recovery
chown system:cache /cache/recovery
chmod 0770 /cache/recovery
rm /cache/recovery/command

# = CPU FREQUENCY CONTROL PERMISSIONS =
chmod 0777 /sys/bus/cpu/devices/cpu0/cpufreq/scaling_min_freq
chmod 0777 /sys/bus/cpu/devices/cpu0/cpufreq/scaling_max_freq
chmod 0777 /sys/bus/cpu/devices/cpu4/cpufreq/scaling_min_freq
chmod 0777 /sys/bus/cpu/devices/cpu4/cpufreq/scaling_max_freq

# ==== CPU FREQUENCY CONTROL LOOP =====
#while true
#do
#	cat /vendor/nvdata/cleanrom/little_core_min_frequency > /sys/bus/cpu/devices/cpu0/cpufreq/scaling_min_freq
#	cat /vendor/nvdata/cleanrom/little_core_max_frequency > /sys/bus/cpu/devices/cpu0/cpufreq/scaling_max_freq
#	cat /vendor/nvdata/cleanrom/big_core_min_frequency > /sys/bus/cpu/devices/cpu4/cpufreq/scaling_min_freq
#	cat /vendor/nvdata/cleanrom/big_core_max_frequency > /sys/bus/cpu/devices/cpu4/cpufreq/scaling_max_freq
#	sleep 5
#done

# Fix HDMI permissions
chmod 0666 /dev/hdmitx
