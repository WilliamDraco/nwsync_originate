# Package

version       = "0.4.0"
author        = "WilliamDraco"
description   = "Takes a nwsync .origin file and re-originates the haks/tlks which went into it."
license       = "MIT"
srcDir        = "src"
bin           = @["nwsync_originate"]


# Dependencies

requires "nim >= 2.2.0"
requires "neverwinter >= 2.0.1"
requires "tiny_sqlite >= 0.2.0"
requires "docopt >= 0.7.1"
