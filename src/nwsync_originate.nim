
import tables, strutils, os, osproc, docopt, streams, parsecfg, options
import reimplLibs, neverwinter/compressedbuf, neverwinter/resref

let args = docopt"""
Takes an nwsync .origin file and reconstructs the hak list accordingly.
Creates folders of hak contents, and then haks of those folders.

Can create from server nwsync repo or from clients who have previously
downloaded the manifest.

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
"""
#Adapted from nwsync --version handling
if args["--version"]:
  const nimble: string   = slurp(currentSourcePath().splitFile().dir & "/../nwsync_originate.nimble")
  const gitBranch: string = staticExec("git symbolic-ref -q --short HEAD").strip
  const gitRev: string    = staticExec("git rev-parse HEAD").strip

  let nimbleConfig        = loadConfig(newStringStream(nimble))
  let packageVersion     = nimbleConfig.getSectionValue("", "version")
  let versionString  = "NWNT " & packageVersion & " (" & gitBranch & "/" & gitRev[0..5] & ", nim " & NimVersion & ")"

  echo versionString
  quit(0)

#read origins file into table(resref:hak)
var
  resHakMap = initTable[string, string]()
  hakList: seq[string]

let origin = $args["<origin>"]
let iniPath = if args["-a"]: $args["-a"] else: ""
let fromClient = args["-c"]
let outdir = $args["<outputDir>"]
let toAlias = args["-d"]

var #doc folders, with defaults for server/no-alias
  hakDir = outdir
  tlkDir = outdir
  nwsyncDir = outdir #unused without alias, but nonetheless..

if toAlias:
  if iniPath == "" or iniPath.extractFilename() != "nwn.ini":
    echo "-a NWN_INI must be provided in order to use alias."
    quit(0)
  let ini = iniPath.openFileStream(fmRead)
  for line in ini.lines():
    if line[0..2] == "HAK":
      hakDir = line[4..^1]
    elif line[0..2] == "TLK":
      tlkDir = line[4..^1]
    elif line[0..5] == "NWSYNC":
      nwsyncDir = line[7..^1]

proc readOrigins(path: string) =
  echo "reading origin file"
  var lastHak: string
  for line in path.lines():
    if line.len == 0: continue
    elif line.startsWith("Erf:"): #if a hak
      let hakname = line[4..^1].extractFilename()
      lastHak = hakname
      hakList.add(hakname)
    elif line.startsWith("\t"): #an entry
      resHakMap[line[1..^1].toLowerAscii()] = lastHak
      if line.len > 12 and line[1..11] == "__erfdup__":
        echo "Original name cannot be recoved for duplicate: " & line[1..^1].toLowerAscii() & ". Recommend de-duplicate in original repo"
    else: #tlk, maybe something else?
      lastHak = "ResFiles"

origin.readOrigins()

#extract files when starting from a server repo
proc originateFromServer(originPath, outDir: string) =
  echo "Extracting files from the server NWSync repository. This may take some time."
  let manifest = readManifest(originPath.changeFileExt(""))

  #Read through manifests, finding resrefs and allocating them to folders
  for mfCount, mfEntry in manifest.entries:
    #first, get the hak set-up
    let resRef = $mfEntry.resRef.resolve().get() #ie abc.mdl //from neverwinter/resref
    let hakFolder = outDir / resHakMap[resRef] & "_f" #just the hak name, not folder. might need to reduce this i.e. without .hak at the end.
    discard existsOrCreateDir(hakFolder) #create the folder if its not there already.
    let resStream = openFileStream(hakFolder / resRef, fmWrite) #check path here includes hakFolder
    #now find the relevent file based on mfEntry.sha1 (See pathForEntry function in nwsync/libupdate)
    let repoPath = manifest.pathForEntry(originPath.parentDir().parentDir(), mfEntry.sha1, false)
    let dataStream = repoPath.openFileStream(fmRead)
    resStream.write(dataStream.decompress(makeMagic("NSYC"))) #decompress from  nwn/compressedbuf
    resStream.close()
    dataStream.close()


if fromClient:
  echo "-c Not yet implemented, sorry"
  quit(0)
else:
  origin.originateFromServer(outdir)

proc hakPacker() =
  #all entries now written out, we're going to straight-up call the hak-making-thingo on the folders
  for packhak in hakList:
    echo "Packing with: -f " & hakDir / packhak & " -c " & outDir / packhak & "_f"
    let packer = startProcess(findExe("nwn_erf"), "", @["-f", hakDir / packhak, "-c", outDir / packhak & "_f"], nil, {poStdErrToStdOut, poUsePath})

    while packer.running:
      for line in packer.outputStream().lines:
        echo line

    if packer.waitForExit != 0:
      echo "Packing of " & packhak & " failed."


  if toAlias:
    for kind, file in walkdir(outDir / "ResFiles_f"):
      if file.splitFile().ext == ".tlk":
        file.copyFileToDir(tlkDir)
      else:
        echo "File alias directory for " & file.extractFilename & " is not yet coded. Please raise a github issue for this."

hakPacker()
