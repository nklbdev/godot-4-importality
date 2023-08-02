# Importality

[![en](https://img.shields.io/badge/lang-en-red.svg)](README.md)
[![en](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

![all_in_one](https://github.com/nklbdev/godot-4-importality/assets/7024016/16a6d973-bf99-4d88-b9a1-d68b72323c3b)
![icon](https://github.com/nklbdev/godot-4-importality/assets/7024016/978a36e8-61e0-406e-8a35-b872eff51be0)

**Importality - is an add-on for [Godot](https://godotengine.org) engine for importing graphics and animations from popular formats.**

## 📜 Table of contents

- [Introduction](#introduction)
- [Features](#features)
- [How to install](#how-to-install)
- [How to use](#how-to-use)
- [How to help the project](#how-to-help-the-project)

## 📝 Introduction

I previously published an [add-on for importing Aseprite files](https://github.com/nklbdev/godot-4-aseprite-importers). After that, I started developing a similar add-on for importing Krita files. During the development process, these projects turned out to have a lot in common, and I decided to combine them into one. Importality contains scripts for exporting data from source files to a common internal format, and scripts for importing data from an internal format into Godot resources. After that, I decide to add new export scripts for other graphic applications.

## 🎯 Features

- Adding recognition of source graphic files as images to Godot with all the standard features for importing them (for animated files, only the first frame will be imported).
- Support for Aseprite (and LibreSprite), Krita, Pencil2D, Piskel and Pixelorama files. Other formats may be supported in the future.
- Import files as:
     - Atlas of sprites (sprite sheet) - texture with metadata;
     - `SpriteFrames` resource to create your own `AnimatedSprite2D` and `AnimatedSprite3D` based on it;
     - `PackedScene`'s with ready-to-use `Node`'s:
         - `AnimatedSprite2D` and `AnimatedSprite3D`
         - `Sprite2D`, `Sprite3D` and `TextureRect` animated with `AnimationPlayer`
- Several artifacts avoiding methods on the edges of sprites.
- Grid-based and packaged layout options for sprite sheets.
- Several node animation strategies with `AnimationPlayer`.

## 💽 How to install

1. Install it from [Godot Asset Library](https://godotengine.org/asset-library/asset/2025) or:
    - Clone this repository or download its contents as an archive.
    - Place the contents of the `addons` folder of the repository into the `addons` folder of your project.
1. Adjust the settings in `Project Settings` -> `General` -> `Advanced Settings` -> `Importality`
     - [Specify a directory for temporary files](https://github.com/nklbdev/godot-4-importality/wiki/about-temporary-files-and-ram_drives-(en)).
     - Specify the command and its parameters to launch your editor in data export mode, if necessary. How to configure settings for your graphical application, see the corresponding article on the [wiki](https://github.com/nklbdev/godot-4-importality/wiki).

## 👷 How to use

**Be sure to read the wiki article about the editor you are using! These articles describe the important nuances of configuring the integration!**
- [Aseprite/LibreSprite](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-aseprite-(en)) (Important)
- [Krita](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-krita-(en)) (**Critical!**)
- [Pencil2D](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-pencil_2d-(en)) (Important)
- [Piskel](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-piskel-(en)) (No integration with the application. The plugin uses its own source file parser)
- [Pixelorama](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-pixelorama-(en)) (No integration with the application. The plugin uses its own source file parser)

Then:

1. Save the files of your favorite graphics editor to the Godot project folder.
1. Select them in the Godot file system tree. They are already imported as a `Texture2D` resource.
1. Select the import method you want in the "Import" panel.
1. Customize its settings.
1. If necessary, save your settings as a default preset for this import method.
1. Click the "Reimport" button (you may need to restart the engine).
1. In the future, if you change the source files, Godot will automatically repeat the import.

## 💪 How to help the project

If you know how another graphics format works, or how to use the CLI of another application, graphics and animation from which can be imported in this way - please offer your help in any way. It could be:

- An [issue](https://github.com/nklbdev/godot-4-importality/issues) describing the bug, problem, or improvement for the add-on. (Please attach screenshots and other data to help reproduce your issue.)
- Textual description of the format or CLI operation.
- [Pull request](https://github.com/nklbdev/godot-4-importality/pulls) with new exporter.
- A temporary or permanent license for paid software to be able to study it and create an exporter. For example for:
     - [Adobe Photoshop](https://www.adobe.com/products/photoshop.html)
     - [Adobe Animate](https://www.adobe.com/products/animate.html)
     - [Adobe Character Animator](https://www.adobe.com/products/character-animator.html)
     - [Affinity Photo](https://affinity.serif.com/photo)
     - [Moho Debut](https://moho.lostmarble.com/products/moho-debut) / [Moho Pro](https://moho.lostmarble.com/products/moho-pro)
     - [Toon Boom Harmony](https://www.toonboom.com/products/harmony)
     - [PyxelEdit](https://pyxeledit.com)
     - and others
