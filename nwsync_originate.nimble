# Package

version       = "0.2.0"
author        = "WilliamDraco"
description   = "Takes a nwsync .origin file and re-originates the haks/tlks which went into it."
license       = "MIT"
srcDir        = "src"
bin           = @["nwsync_originate"]


# Dependencies

requires "nim >= 1.4.2"
requires "neverwinter >= 1.4.1"
requires "tiny_sqlite >= 0.1.2"
