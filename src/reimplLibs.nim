# functions/procs re-implemented from their nwsync counterparts because nwsync is not a library.


############### streamext ##################################################
import streams

type SizePrefix* = uint8 | uint16 | uint32 | uint64

proc readString*(io: Stream, size: int): string =
  result = readStr(io, int size)
  if result.len.int != size.int:
    raise newException(IOError, "wanted to read T of length " &
                                $size & ", but got " & $result.len)

proc readArray*[Length: static[int], T](io: Stream, reader: proc(): T): array[0..Length-1, T] =
  for i in 0..<Length:
    result[i] = reader()

#################### libmanifest ################################
import streams, std/sha1, neverwinter/restype, neverwinter/resref, strutils,
  options

const HashTreeDepth = 2 # this needs to match with the nwn sources

const Version = 3
# Binary Format: version=3
#
#   Manifest:
#     uint32            version
#     uint32            count of ManifestEntries
#     uint32            count of ManifestMappings
#     ManifestEntry[]   count entries
#     ManifestMapping[] count additional mappings
#
#   ManifestEntry: (sorted)
#     byte[20]          SHA1 (as raw bytes) of resref
#     uint32            size (bytes)
#     char[16]          resref (WITHOUT extension)
#     uint16            restype
#
#   ManifestMapping: (sorted)
#     uint32            Index into ManifestEntry array
#     char[16]          resref (WITHOUT extension)
#     uint16            restype
#
# End of version=3

type
  ManifestEntry* = ref object
    sha1*: string
    size*: uint32
    resref*: ResRef

  Manifest* = ref object
    version: uint32
    hashTreeDepth: uint32
    entries*: seq[ManifestEntry]

  ManifestError* = object of ValueError

template check(cond: untyped, msg: string) =
  bind instantiationInfo
  {.line: instantiationInfo().}:
    if not cond:
      raise newException(ManifestError, msg)

proc newManifest*(hashTreeDepth: uint32 = HashTreeDepth): Manifest =
  new(result)
  result.version = Version
  result.entries = newSeq[ManifestEntry]()
  result.hashTreeDepth = hashTreeDepth

proc readResRef(io: Stream): ResRef =
  let resref = io.readString(16).strip(leading=false,trailing=true,chars={'\0'}).toLowerAscii
  let restype = ResType io.readUInt16()
  newResRef(resref, restype)

proc readManifest*(io: Stream): Manifest =
  result = newManifest()

  let magic = io.readString(4)
  check(magic == "NSYM", "Not a manifest (invalid magic bytes)")

  result.version = io.readUint32()
  check(result.version == Version, "Unsupported manifest version " & $result.version)

  let entryCount = io.readUint32()
  let mappingCount = io.readUint32()

  check(entryCount > 0u, "No entries in manifest. This is not supported.")

  for i in 0..<entryCount:
    let sha1 = SecureHash readArray[20, uint8](io) do -> uint8:
      io.readUInt8()
    let sha1str = toLowerAscii($sha1)
    let size = io.readUint32()
    let rr = io.readResRef()

    check(rr.resolve().isSome, "Entry at position " & $i &
      " does not resolve to a valid resref: " & escape($rr))

    let ent = ManifestEntry(sha1: sha1str, size: size, resRef: rr)
    result.entries.add(ent)

  if mappingCount > 0u:
    for i in 0..<mappingCount:
      let index = io.readUint32()
      let rr = io.readResRef()

      check(index.int >= 0 and index.int < result.entries.len,
        "Mapping " & $i & " references non-existent entry " & $index)

      let mf = result.entries[int index]

      let ent = ManifestEntry(sha1: mf.sha1, size: mf.size, resRef: rr)
      result.entries.add(ent)

proc readManifest*(file: string): Manifest =
  try:
    readManifest(newFileStream(file, fmRead))
  except:
    raise newException(IOError, "Origin file must be in server_repo/manifest")


################## libupdate #####################
import os
proc pathForEntry*(manifest: Manifest, rootDirectory, sha1str: string, create: bool): string =
  result = rootDirectory / "data" / "sha1"
  for i in 0..<manifest.hashTreeDepth:
    let pfx = sha1str[i*2..<(i*2+2)]
    result = result / pfx
    if create: createDir result
  result = result / sha1str


##### https://github.com/nim-lang/Nim/issues/14810 #####
proc toString*(bytes: openarray[byte]): string =
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)
