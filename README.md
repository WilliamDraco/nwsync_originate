# nwsync_originate
A third-party tool for utilising the origin files of nwsync (post v3) to recreate Haks from server or client repositories.

Takes an nwsync .origin file and reconstructs the hak list accordingly, creating folders with all of the hak contents, and then also haks of those folders.

Can re-originate from the origin server nwsync repo, or from client nwsync repositiories so long as they have previously downloaded the correct manifest.

Note due to pre-release status of nwsync v3 which includes origins there may be changes, and indeed origins might be removed entirely - But for now, there's this.

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
