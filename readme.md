# Explorer v0.1.12
---

[![Written in: Fantom](http://img.shields.io/badge/written%20in-Fantom-lightgray.svg)](https://fantom-lang.org/)
[![pod: v0.1.12](http://img.shields.io/badge/pod-v0.1.12-yellow.svg)](http://eggbox.fantomfactory.org/pods/afExplorer)
[![Licence: ISC](http://img.shields.io/badge/licence-ISC-blue.svg)](https://choosealicense.com/licenses/isc/)

## Overview

`Explorer` is a file explorer application based on the [Reflux](http://eggbox.fantomfactory.org/pods/afReflux) framework. More than an application, Explorer also provides reusable Views and Editors. Explorer may also be enhanced through the use of Plugins.

Features:

* System file explorer
* Fantom documentation viewer
* A better web browser / html viewer
* Fandoc file viewer
* Resource Tree
* Text editor (borrowed from [fluxText](https://fantom.org/doc/fluxText/index.html))
* Syntax highlighting (uses [syntax](https://fantom.org/doc/syntax/index.html))


Small things that make me use it:

* Quick view / edit toggling with F12
* Easily show / hide hidden files
* Text editor word wrapping (configurable)
* Address bar accepts pod names, e.g. `afIoc`


## <a name="Install"></a>Install

Install `Explorer` with the Fantom Pod Manager ( [FPM](http://eggbox.fantomfactory.org/pods/afFpm) ):

    C:\> fpm install afExplorer

Or install `Explorer` with [fanr](https://fantom.org/doc/docFanr/Tool.html#install):

    C:\> fanr install -r http://eggbox.fantomfactory.org/fanr/ afExplorer

To use in a [Fantom](https://fantom-lang.org/) project, add a dependency to `build.fan`:

    depends = ["sys 1.0", ..., "afExplorer 0.1"]

## <a name="documentation"></a>Documentation

Full API & fandocs are available on the [Eggbox](http://eggbox.fantomfactory.org/pods/afExplorer/) - the Fantom Pod Repository.

## Quick Start

Simply start Explorer from the command line:

    C:\> fan afExplorer
    
    [afIoc] Adding module definition for afReflux::RefluxModule
    [afIoc] Adding module definition for afExplorer::ExplorerModule
       ___    __                 _____        _
      / _ |  / /_____  _____    / ___/__  ___/ /_________  __ __
     / _  | / // / -_|/ _  /===/ __// _ \/ _/ __/ _  / __|/ // /
    /_/ |_|/_//_/\__|/_//_/   /_/   \_,_/__/\__/____/_/   \_, /
                                         Explorer v0.0.4 /___/
    
    IoC Registry built in 216ms and started up in 10ms
    

![Example Screenshot](http://eggbox.fantomfactory.org/pods/afExplorer/doc/screenshot.png)

Explorer may optionally be started with a list of URIs to be opened up in tabs:

    C:\> fan afExplorer C:\Temp
    
    C:\> fan afExplorer http://www.fantomfactory.org/
    
    C:\> fan afExplorer afIoc::Registry
    

## Usage

Following Reflux browser behaviour, entering valid URIs in the address bar will bring up an associated View for that resource.

If there are multiple Views available for the resource, a drop down will appear in the address bar allowing you to toggle between them:

![View Dropdowns](http://eggbox.fantomfactory.org/pods/afExplorer/doc/viewDropDown.png)

You may also specify the view by adding a query parameter to the URI:

    file:/C:/Projects/Explorer/pod.fdoc?view=afExplorer::TextEditor

You may also specify a URI to be opened in a new tab, regardless of if the view is configured for re-use or not:

    file:/C:/Projects/Explorer/pod.fdoc?newTab=true

### File Explorer

Explorer may be used to explore your file system using the `file:` scheme. URIs should be absolute and the path should begin with a `/`.

    file:/C:/Projects/Explorer/

You may also enter an OS specific path:

    C:\Projects\Explorer

Files may be opened up in a:

* Text Editor
* HTML Viewer
* Fandoc Viewer
* Image Viewer


### Web Browser

Explorer may also be used as a (basic) web browser by entering a `http:` scheme:

![Web Browser](http://eggbox.fantomfactory.org/pods/afExplorer/doc/webBrowser.png)

### <a name="fandocViewer"></a>Fandoc Viewer

Explorer can view all the Fantom documentation held in the current Fantom installation. This includes all the API docs for all the installed pods. It uses a `fandoc:` scheme with the following format:

    fandoc:/<pod>/<type>/<slot>
    
    fandoc:/afReflux/View/onLoad

The address bar also accepts simple fandoc notation (case insensitive):

    afReflux
    
    afReflux::View

![Fandoc Viewer](http://eggbox.fantomfactory.org/pods/afExplorer/doc/fandocViewer.png)

Press `F1` at anytime to being up the Fandoc index.

## <a name="plugins"></a>Plugins

Exoplorer may be customised though *Plugins*.

A plugin is any Fantom pod that defines an index property of `afExplorer.module`, the value of which should be the qualified type name an IoC `AppModule`.

    index = [ "afExplorer.module" : "myExplorerPlugin::PluginModule" ]

On startup, Explorer scans the current Fantom installation for these pods and automatically adds them to its IoC module list. These plugin modules may then configure *anything* a reflux application can.

