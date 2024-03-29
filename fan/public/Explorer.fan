using afIoc
using afReflux
using gfx
using fwt

** (Service) - 
** The main service API for Explorer operations.
mixin Explorer {
	abstract File rename(File file)
	abstract Void delete(File file)
	abstract Void cut(File file)
	abstract Void copy(File file)
	abstract Void paste(File destDir)
	
	** Returns a unique file that (currently) does not exist on the file system.
	abstract File uniqueFile(File destFile)
	
	** Opens a dialogue for the file name before creating an empty file.
	** File name defaults to 'NewFile.txt'.
	** 
	** Returns 'null' if dialogue was cancelled.	
	abstract File? newFile(File containingFolder, Str? defFileName := null)
	
	** Opens a dialogue for the folder name before creating an empty folder.
	** Folder name defaults to 'NewFolder'.
	abstract Void newFolder(File containingFolder, Str? defFolderName := null)

	abstract Void openFileInSystem(File file)

	abstract Void compressToZip(File toCompress, File dst)

	abstract Void compressToGz(File toCompress)
	
	abstract Image fileToIcon(File f)
	abstract Image urlToIcon(Uri url)

	abstract ExplorerPrefs preferences()

	** Returns a cached version of 'File.osRoots' that is updated every other second *at most*.
	abstract File[] osRoots()

	@NoDoc	// is there a way around having this method?
	abstract Bool pasteEnabled()
}
	
internal class ExplorerImpl : Explorer {

	@Inject private ExplorerEvents		events
	@Inject private Scope				scope
	@Inject private RefluxIcons			icons
	@Inject private Images				images
	@Inject private Preferences			prefs
	@Inject private Reflux				reflux
	@Inject private Errors				errors
	@Inject private Dialogues			dialogues
	@Inject private |->GlobalCommands|	globalCommands
			private Duration			osRootsLastUpdated
			private File[]				osRootsCached
	static	const	Uri					fileIconsRoot	:= `fan://afExplorer/res/icons-file/`
	static 	const	Int 				bufferSize 		:= 16 * 1024

	internal File? copiedFile
	internal File? cutFile
	

	new make(|This| in) {
		in(this)
		osRootsCached 		= File.osRoots.map { it.normalize }
		osRootsLastUpdated	= Duration.now
	}

	override File rename(File file) {
		newName := openRenameDialog(file)
		if (newName != null && newName != file.name) {
			
			// can't rename a file to the same (case insensitive) name
			// so, rename it twice
			if (newName.equalsIgnoreCase(file.name)) {
				tmpName := newName + Int.random(0..9999).toStr
				file = file.rename(tmpName)
			}

			newFile := file.rename(newName)
			
			if (file.parent != null)
				reflux.refresh(reflux.resolve(file.parent.uri.toStr))
			events.onRename(file, newFile)
			return newFile
		}
		return file
	}
	
	private Str? openRenameDialog(File file) {
		field := Text { it.text = file.name; it.prefCols = 20 }
		pane  := GridPane {
			numCols = 2
			expandCol = 1
			halignCells=Halign.fill
			Label { text="Original name:" },
			Text { it.text = file.name; it.prefCols = 20; it.editable = false; it.border = false },
			Label { text="Rename to:" },
			field,
		}
		field.onAction.add |Event e| { e.widget.window.close(dialogues.ok) }
		r := dialogues.openMsgBox(Dialog#.pod, "question", pane, null, dialogues.okCancel) |Dialog diag| {
			diag.title = file.isDir ? "Rename Folder" : "Rename File"
			diag.image = images.get(`fan://afExplorer/res/icons/` + (file.isDir ? `folder-horizontal-x32.png` : `document-x32.png`), false)
			diag.onOpen.add {
				field.focus
			}
		}
		if (r != dialogues.ok) return null
		return field.text
	}

	override Void delete(File file) {
		okay := dialogues.openQuestion("Delete ${file.name}?\n\n${file.osPath}", null, dialogues.yesNo)
		if (okay == dialogues.yes) {
			file.delete
			if (file.parent != null)
				reflux.refresh(reflux.resolve(file.parent.uri.toStr))
		}
	}

	override Void cut(File file) {
		cutFile		= file
		copiedFile	= null
		globalCommands()["afReflux.cmdPaste"].update
	}

	override Void copy(File file) {
		cutFile		= null
		copiedFile	= file
		globalCommands()["afReflux.cmdPaste"].update
	}

	override Void paste(File destDir) {
		// TODO dialog for copy overwrite options
		if (cutFile != null) {

			// if we're moving ourself, to ourself - just return!
			if (cutFile.parent == destDir)
				return
			
			if (destDir.isDir == false)
				throw IOErr("Can not move to inside a file!")
				
			if (destDir.toStr.contains(cutFile.toStr))
				throw IOErr("Can not move dir to inside itself!")
			
			cutFile.moveInto(destDir)
			cutFile = null
		}

		if (copiedFile != null) {
			if (copiedFile.isDir == false) {
				if (destDir.isDir == false) {
					destFile := uniqueFile(destDir)
					copiedFile.copyTo(destFile)
				}
				
				if (destDir.isDir == true) {
					destFile := uniqueFile(destDir + copiedFile.name.toUri)
					copiedFile.copyTo(destFile)
				}
			}
			if (copiedFile.isDir == true) {
				if (destDir.isDir == false) 
					throw IOErr("Can not copy a dir into a file")
				
				if (destDir.isDir == true) {
					destFile := uniqueFile(destDir.plus(copiedFile.name.toUri, false))

					if (destFile.toStr.contains(copiedFile.toStr))
						throw IOErr("Can not copy dir to inside itself!")
					
					copiedFile.copyTo(destFile)
				}
			}
			
			// once copied, allow multiple pastes by NOT setting it to null
			// copiedFile = null
		}
		reflux.refresh(reflux.resolve(destDir.uri.toStr))
	}
	
	override File uniqueFile(File file) {
		destFile := file
		destName := destFile.name.toUri
		fileIndex := 0
		while (destFile.exists) {
			fileIndex++
			if (destFile.ext == null)
				destName = `${file.name}($fileIndex)`
			else
				destName = `${file.basename} ($fileIndex).${file.ext}`
			destFile = destFile.parent + destName
			if (file.isDir)
				destFile = destFile.uri.plusSlash.toFile
		}
		return destFile
	}

	override File? newFile(File containingFolder, Str? defFileName := null) {
		fileName := dialogues.openPromptStr("New File", defFileName ?: "NewFile.txt")
		if (fileName != null) {
			newFile := containingFolder.createFile(fileName)
			reflux.refresh(reflux.resolve(containingFolder.uri.toStr))
			return newFile
		}
		return null
	}

	override Void newFolder(File containingFolder, Str? defFolderName := null) {
		dirName := dialogues.openPromptStr("New Folder", defFolderName ?: "NewFolder")
		if (dirName != null) {
			containingFolder.createDir(dirName)
			reflux.refresh(reflux.resolve(containingFolder.uri.toStr))
		}
	}
	
	override Void openFileInSystem(File file) {
		Desktop.launchProgram(file.uri)
	}
	
	override Void compressToGz(File toCompress) {
		if (toCompress.isDir)
			throw ArgErr("Cannot gzip directories: $toCompress")
		
		scope := scope
		pd := (ProgressDialogue) scope.build(ProgressDialogue#)
		pd.title = "Compress to .gz"
		pd.image = Image(`fan://afExplorer/res/images/zip.x48.png`)
		pd.open(reflux.window) |ProgressWorker worker| {
			locale		:= (LocaleFormat) scope.serviceById(LocaleFormat#.qname)
			explorer	:= (Explorer) 	  scope.serviceById(Explorer#.qname)

			worker.update(0, 0, "Zipping ${toCompress.normalize.osPath} (${locale.fileSize(toCompress.size)})")
			dst		:= toCompress.uri.plusName(toCompress.name + ".gz").toFile
			dest	:= explorer.uniqueFile(dst)
			
			bTotal	:= toCompress.size
			bRead	:= 0
			zipIn	:= toCompress.in(bufferSize)
			zipOut	:= Zip.gzipOutStream(dest.out(false, bufferSize))

			try {
				buf	 := Buf(bufferSize)
				piping := true
				
				while (piping) {
					i := zipIn.readBuf(buf.seek(0), bufferSize)
					if (i == null) {
						piping = false
						continue
					}
					bRead += i
					zipOut.writeBuf(buf.seek(0), i)
					worker.update(bRead, bTotal)
				}
				
			} finally {
				zipIn.close
				zipOut.close
			}

			worker.update(100, 100, "Written ${dest.normalize.osPath} (${locale.fileSize(dest.size)})")
			worker.update(100, 100, "Done.")

			Desktop.callAsync |->| {
				reflux := (Reflux) scope.serviceById(Reflux#.qname)
				reflux.refresh
			}
		}
	}
	
	override Void compressToZip(File toCompress, File dst) {
		if (dst.isDir)
			throw ArgErr("Cannot write to $dst")
		
		scope := scope
		pd := (ProgressDialogue) scope.build(ProgressDialogue#)
		pd.title = "Compress to .zip"
		pd.image = Image(`fan://afExplorer/res/images/zip.x48.png`)
		pd.open(reflux.window) |ProgressWorker worker| {
			locale		:= (LocaleFormat) scope.serviceById(LocaleFormat#.qname)
			explorer	:= (Explorer) 	  scope.serviceById(Explorer#.qname)

			worker.update(0, 0, "Zipping ${toCompress.normalize.osPath}")
			worker.update(0, 0, "Inspecting source files...")

			noOfFiles := 0
			noOfBytes := 0
			toCompress.walk |src| {
				if (!src.isDir) {
					noOfFiles++
					noOfBytes += src.size
				}
			}
			worker.update(0, 0, "Found $noOfFiles files with a sum total of ${locale.fileSize(noOfBytes)}")

			dest := explorer.uniqueFile(dst)
			zip  := Zip.write(dest.out)
			buf	 := Buf(bufferSize)
			// don't include the name of the containing folder in zip paths
			parentUri := toCompress.isDir ? toCompress.uri : toCompress.parent.uri
			try {
//				fileList	 := Str[,]
				bytesWritten := 0

				worker.update(bytesWritten, noOfBytes, "Compressing files...")
				toCompress.walk |src| {
					if (src.isDir) return

					path := src.uri.relTo(parentUri)
					// don't append path to detail path, cause Java Heap Space probs with big dirs ~ 24,000 files
//					worker.update(bytesWritten, noOfBytes, "Compressing ${path}")
					worker.update(bytesWritten, noOfBytes)

					out := zip.writeNext(path)
					try {
						// this is the easy way to compress the file - but we do it the hard way
						// so we can show progress when zipping large files
//						src.in(bufferSize).pipe(out)
						
						in := src.in 
						piping := true
						while (piping) {
							bytesRead := readFile(src, in, buf, worker)
							if (bytesRead == null)
								piping = false
							else {
								out.writeBuf(buf.flip)
								bytesWritten += bytesRead
								worker.update(bytesWritten, noOfBytes)
							}
						}
						
					} finally
						out.close
				}
			} finally
				zip.close

			worker.update(100, 100, "Written ${dest.normalize.osPath} (${locale.fileSize(dest.size)})")
			worker.update(100, 100, "Done.")

			Desktop.callAsync |->| {
				reflux := (Reflux) scope.serviceById(Reflux#.qname)
				reflux.refresh
			}
		}
	}
	
	private static Int? readFile(File src, InStream in, Buf buf, ProgressWorker worker) {
		try {
			return in.readBuf(buf.clear, bufferSize)
		} catch (IOErr ioe) {
			worker.warn("Problems reading: ${src.osPath}\n  ${ioe.msg}\n")
			return null
		}
	}
	
	static const Str[] imageExts := "bmp jpg jpeg gif png".split
	override Image fileToIcon(File f) {
		hidden := preferences.isHidden(f)

		if (f.isDir) {
			// can't cache osRoots 'cos it changes with flash drives et al
			name := osRoots.contains(f) ? "icoFolderRoot" : "icoFolder"
			return hidden ? icons.getFaded(name) : icons.get(name)
		}
		
		// if the image is small enough ~5k, return a thumbnail as the icon
		// .svg files and the like cause ugly stack traces as FWT logs the Err before returning null... Grrr!!
		if (imageExts.contains(f.ext ?: "") && f.size < (5 * 1024)) {
			if (images.contains(f.uri))
				return hidden ? images.getFaded(f.uri) : images.get(f.uri)

			icon := (Image?) images.load(f.uri, false)
			if (icon != null) {
				if (icon.size == Size(16, 16)) {
					images[f.uri] = icon
					return icon
				}

				// note we have to return a 16x16 image else SWT scales it for us
				if (icon.size.w <= 16 && icon.size.h <= 16) {
					newIcon := Image(Size(16, 16)) |Graphics g| {
						g.drawImage(icon, (16 - icon.size.w) / 2, (16 - icon.size.h) / 2)
					}
					images[f.uri] = newIcon
					return newIcon
				}

				if (icon.size.w >= icon.size.h) {
					newH := icon.size.h * 16 / icon.size.w
					if (newH > 0) {	// really wide images don't scale well!
						newIcon := icon.resize(Size(16, newH))
						if (newH < 16) {
							newIcon = Image(Size(16, 16)) |Graphics g| {
								g.drawImage(newIcon, 0, (16 - newH) / 2)
							}
						}
						images[f.uri] = newIcon
						return newIcon
					}
				}

				if (icon.size.w <= icon.size.h) {
					newW := icon.size.w * 16 / icon.size.h
					if (newW > 0) {	// really tall images don't scale well!
						newIcon := icon.resize(Size(newW, 16))
						if (newW < 16) {
							newIcon = Image(Size(16, 16)) |Graphics g| {
								g.drawImage(newIcon, (16 - newW) / 2, 0)
							}
						}
						images[f.uri] = newIcon
						return newIcon
					}
				}				
			}
		}
		
		// look for explicit match based off ext
		if (f.ext != null) {
			icon := fileIcon("file${f.ext.capitalize}.png", hidden)
			if (icon != null) return icon
		}
		
		mimeType := f.mimeType?.noParams
		if (mimeType != null) {
			mime := mimeType.mediaType.fromDisplayName.capitalize + mimeType.subType.fromDisplayName.capitalize
			icon := fileIcon("file${mime}.png", hidden)
			if (icon != null) return icon

			mime = mimeType.mediaType.fromDisplayName.capitalize
			icon = fileIcon("file${mime}.png", hidden)
			if (icon != null) return icon
		}

		action := preferences.fileActions.find { it.matchesExt(f.ext) }
		if (action != null) {
			launcher := preferences.fileLaunchers.find { it.id == action.launcherId }
			if (launcher != null)
				return icons.fromUri(launcher.iconUri, false)
		}

		return fileIcon("file.png", hidden)
	}
	
	override Image urlToIcon(Uri url) {
		// look for explicit match based off ext
		if (url.ext != null) {
			icon := fileIcon("file${url.ext.capitalize}.png", false)
			if (icon != null) return icon
		}
		
		mimeType := url.mimeType?.noParams
		if (mimeType != null) {
			mime := mimeType.mediaType.fromDisplayName.capitalize + mimeType.subType.fromDisplayName.capitalize
			icon := fileIcon("file${mime}.png", false)
			if (icon != null) return icon

			mime = mimeType.mediaType.fromDisplayName.capitalize
			icon = fileIcon("file${mime}.png", false)
			if (icon != null) return icon
		}

		return fileIcon("fileTextHtml.png", false)
	}

	override once ExplorerPrefs preferences() {
		prefs.loadPrefs(ExplorerPrefs#, "afExplorer.fog")
	}
	
	override File[] osRoots() {
		if (Duration.now - osRootsLastUpdated > 2sec) {
			this.osRootsCached = File.osRoots.map { it.normalize }		
			this.osRootsLastUpdated = Duration.now
		}
		return osRootsCached
	}

	private Image? fileIcon(Str fileName, Bool hidden) {
		uri := fileIconsRoot.plusName(fileName)
		return hidden ?	images.getFaded(uri, false) : images.get(uri, false)
	}
	
	override Bool pasteEnabled() {
		copiedFile != null || cutFile != null
	}
}
