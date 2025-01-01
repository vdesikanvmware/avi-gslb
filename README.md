This script is used to setup AVI GSLB DNS for App Engine in shepherd airgapped environment.  GLSB site appengine.tanzu.io will be setup by this script. 
**Steps**
1. sheepctl lock ssh -n tpsm <Lock_ID> -m airgap_jumper
2. git clone https://github.com/vdesikanvmware/avi-gslb.git
3. cd avi-gslb
4. chmod +x avi_gslb.sh
5. ./avi_gslb.sh
