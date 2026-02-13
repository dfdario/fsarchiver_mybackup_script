Description

This script is derived from the two's available at: https://github.com/lexo-ch/fsarchiver-encrypted-full-system-backup-script-with-email-monitoring and https://github.com/AndresDev859674/boot-repair. I would like to thank their developers here. 
I have taken some parts of their scripts to cover my needs for doing complete backups and restores with fsarchiver and even grub boot repair of my and my friends' systems.
On all my PC's I use Manjaro as my preferred operating system which is a distribution derived from Archlinux. Due to that, I can't use qt-fsarchiver because it was developed for other distributions.
What I appreciate a lot of fsarchiver is the ability to perform restores even on smaller devices which no other freely available software has.
Although I'm not very confident in programming with bash, with the help of what's available online and some remids of my past programming activities, I was able to write the lines of code necessary to have a usable program, I hope even for beginners.
If anyone can improve it I would appreciate it.

Disclaimer

This script is intended as a frontend of fsarchiver backup/restore program available at http://www.fsarchiver.org.
This software is provided “as is”, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and non-infringement.
In no event shall the author be liable for any claim, damages or other liability, whether in an action of contract, tort or otherwise, arising from, out of or in connection with the software or the use or other dealings in the software.
It is granted the right to freely distribute and modify this software with the sole requirement that the same rights be preserved.
I created this software for personal use, as there was no other similar software that could meet my needs.
I'm sharing it with you in the hope that you find it useful.

	Dario (Italy)

HOWTO RUN IT
1. Download the script from this site
2. Make it executable with command: chmod +x fsarchiver_mybackup.sh
3. Run with sudo: sudo ./fsarchiver_mybackup.sh
4. Be very careful in what you are doing because a small mistake may damage your system!

