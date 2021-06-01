# nwsync_originate
A third-party tool for utilising the origin files of nwsync (post v3) to recreate Haks from server or client repositories.

Takes an nwsync .origin file and reconstructs the hak list accordingly, creating folders with all of the hak contents, and then also haks of those folders. It can re-originate from the origin server nwsync repo, or from client nwsync repositiories so long as they have previously downloaded the correct manifest. The outputDir will be cleared of all folders/files which are not part of the currently processing origin.

Please be aware that re-origination does not result in exact replicas of the original haks. Origin files do not include any file not used by resman, which will exclude shadowed resources. In some cases, this can result in entire hak files being removed - However, be aware that this is intelligent deduplication, and never results in "lost" files which were in use. (Warnings regarding \_\_erfdup\_\_ files are in relation to duplicates which appear within a single erf/hak)


**REQUIRES**
nwsync_originate utilises nwn_erf from the neverwinter.nim tools (https://github.com/niv/neverwinter.nim/releases) in order to pack the hak contents. Ensure nwn_erf is available in PATH or placed in the same directory as nwsync_originate.

This can be set-up to run via s script. A Windows Batch script (to be run from the nwsync_originate directory) is below, but would require little change for unix. Be sure to edit the IP and file-paths as required.
```
powershell wget http://nwsync.ip.address.here/latest -OutFile latest.txt
set /p neworigin=< latest.txt
powershell wget http://nwsync.ip.address.here/manifests/%neworigin%.origin -OutFile %neworigin%.origin
nwsync_originate %neworigin%.origin C:\file\output\path -a "C:\Users\username\Documents\Neverwinter Nights\nwn.ini" -d -c
```

```
Usage:
  nwsync_originate <origin> <outputDir> [options]
  nwsync_originate -h | --help
  nwsync_originate --version

Options:
  -a NWN_INI  Path to nwn.ini to find Alias for /hak, /tlk and /nwsync as
              required (see below)

  -d          Flag for .hak and .tlk to be placed in their alias Directory.
              Else places haks in outputDir. Requires -a switch.

  -c          By default, we attempt to re-originate from a server nwsync
              repo. This flag attempts from the client /nwsync which must have
              previously downloaded the same origin manifest. Requires -a
              switch
```
