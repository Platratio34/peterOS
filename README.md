# PeterOS

A Computer-Craft operating system


**[Getting Started](https://github.com/Platratio34/peterOS/wiki/Getting-Started)**

## Features

- Networking
- GUI package
- Program installation
- "Users"
- Helpful libraries

## Installation

To install PeterOS run the following command on a computer:

```console
wget run https://raw.githubusercontent.com/Platratio34/peterOS/master/networkInstaller.lua
```

If PeterOS is already installed, run the following command to update it:
```console
osUpdate y
```

## Pgm-get

Program Get (pgm-get) is the program installation tool for PeterOS.
It comes pre-installed on the operating system and can be accessed via:
```console
pgm-get [update|upgrade|install|uninstall|list]
```
For more information see the [pgm-get repository](https://github.com/peterOS-pgm-get/pgm-get)

## Networking

PeterOS has a built in networking package based on real life IP systems.

For more information see the [network wiki page](https://github.com/Platratio34/peterOS/wiki/Networking)

## Users-like system

PeterOS has a user like system, although it only has 2 users: regular and super.
Some operations like editing operating system files and installing programs with pgm-get require you to log in as super via either `su` or `sudo`

For more information see the user wiki page

## Libraries

- [Improved string library](https://github.com/Platratio34/peterOS/wiki/String-library)
- SHA256 hashing `pos.require(hash.sha256)`
- ECC encryption (used for networking) `pos.require(eec)`
- Config `pos.Config()`
- Logger `pos.Logger()`
- CLI Parser `pos.Parser()`

## Graphical User Interface Package

PeterOS has a window based GUI package under `pos.gui`.
The package can be used to easily make simple GUIs for programs using an Object Oriented ideology.

For more information see the GUI section of the wiki
