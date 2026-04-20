# Project-Downloader
Scratch Project downloader that supports (currently not) many websites.

Contribute by adding more websites and making the code not dog%&$£.

# Dependencies :
Node.JS for local unpackaging
Bash **OR** Microsoft Powershell
Python3 and JQ for the Bash script
# Usage
## Powershell
You will need to change the Execution Policy to allow local unsigned scripts (You can switch to default after running the script if you want).
This will only be needed once for one machine.
1. Open Powershell as Root or Administrator
2. Run `Set-ExecutionPolicy RemoteSigned`

Run the script
1. Open Powershell in the directory of the script (Don't use administrator privileges if you can.)
2. Run `./project-downloader.ps1`
## Bash
You will need to give the script execution permissions.
This will only be needed once for the script by running `chmod +x project-downloader.sh` with a user that can do that.

Run the script with `./project-downloader.sh`


This project uses the [Turbowarp Unpackager](https://github.com/TurboWarp/unpackager) which is licensed under [MPL2](http://mozilla.org/MPL/2.0/).
