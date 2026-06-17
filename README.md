DockSettings
============

DockSettings is shell script intended to be used by handheld users with an external GPU. 

Put the script in your Documents folder, and the 99-...rules file in the /etc/udev/rules.d/ folder.

The script will auto backup configuration files from Proton Prefixes (seperate backups for iGPU/eGPU usage) and apply them depending on which GPU is being used.
You can also add additional files/folders to track in the .csv file.

### Credits
Huge thanks to msterbi for the original idea and work!
