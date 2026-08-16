DockSettings
============

DockSettings is shell script intended to be used by handheld users with an external GPU. 

Put the script in your Documents folder, and the 99-...rules file in the /etc/udev/rules.d/ folder.

You may also change the ROOT directory within the script if you do not want to use ~/Documents. 

The script will auto backup configuration files and shader cache from Proton Prefixes (seperate backups for iGPU/eGPU usage) and apply them depending on which GPU is being used.
You can also add additional files/folders to track in the .csv file.

You'd ideally want this script to be called whenever you switch GPUs. The udev rule can work for this, but I personally use Steam shortcuts with launch parameters for more direct control.

### Credits
Huge thanks to msterbi for the original idea and work!

AI DISCLOSURE: AI was used for parts of the script to save time
