# Importality

[![en](https://img.shields.io/badge/lang-en-red.svg)](README.md)
[![en](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

![art for repo 2](https://github.com/nklbdev/godot-4-importality/assets/7024016/f44d98b1-116c-493e-8108-2138b1bddd61)

**Importality - это дополнение (addon) для движка [Godot](https://godotengine.org) для импорта графики и анимации из популярных форматов.**

## 📜 Содержание

- [Вступление](#вступление)
- [Возможности](#возможности)
- [Как установить](#как-установить)
- [Как использовать](#как-использовать)
- [Как помочь проекту](#как-помочь-проекту)

## 📝 Вступление

Ранее я уже публиковал [дополнение для импорта файлов Aseprite](https://github.com/nklbdev/godot-4-aseprite-importers). После него я начал разработку аналогичного дополнения для импорта файлов Krita. В процессе разработки у этих проектов оказалось много общего, и я решил объединить их в один. Importality содержит скрипты экспорта данных из исходных файлов в общий внутренний формат, и скрипты импорта из внутреннего формата в ресурсы Godot. После этого было решено добавить новые скрипты экспорта для других графических приложений.

<p align="center">
<a href="http://www.youtube.com/watch?feature=player_embedded&v=tlfhlQPr_IA" target="_blank">
<img src="http://img.youtube.com/vi/tlfhlQPr_IA/hqdefault.jpg" alt="Watch the demo video" />
</a>
</p>

## 🎯 Возможности

- Добавление в Godot распознавания исходных графических файлов как изображений со всеми штатными возможностями их импорта (для анимированных файлов импортируется только первый кадр).
- Поддержка файлов Aseprite (и LibreSprite), Krita, Pencil2D, Piskel и Pixelorama. В будущем возможна поддержка других форматов.
- Импорт файлов в качестве:
    - Атласа спрайтов (sprite sheet) - текстуры с метаданными;
    - Ресурса `SpriteFrames` для создания собственных `AnimatedSprite2D` и `AnimatedSprite3D` на его основе;
    - Запакованных сцен (`PackedScene`) с готовыми для использования узлами (`Node`):
        - `AnimatedSprite2D` и `AnimatedSprite3D`
        - `Sprite2D`, `Sprite3D` и `TextureRect`, анимированных с помощью `AnimationPlayer`
- Несколько методов борьбы с артефактами по краям спрайтов.
- Табличный и упакованный варианты раскладки атласа спрайтов.
- Несколько стратегий анимации узлов с помощью `AnimationPlayer`.
- Импорт любых других графических форматов как обычных изображений с помощью внешних утилит командной строки

## 🥁 Ближайшие нововведения по [просьбам пользователей Reddit](https://www.reddit.com/r/godot/comments/160hnuj/what_features_should_i_add_to_importality_first)

1. [Фильтры имен слоёв (для переопределения видимости слоёв)](https://github.com/nklbdev/godot-4-importality/issues/11)
1. [Скрипты под Linux и MacOS для запуска Krita от имени другого пользователя](https://github.com/nklbdev/godot-4-importality/issues/6) (для того, чтобы импорт не "зависал", пока запущено окно Krita)
1. Что-то еще (что именно?) - пользователи не определились
1. [Новые целевые типы ресурсов](https://github.com/nklbdev/godot-4-importality/issues/14)
1. [Более гибкая настройка рамок вокруг спрайтов](https://github.com/nklbdev/godot-4-importality/issues/12)
1. [Возможность указать имя слоя с картой нормалей](https://github.com/nklbdev/godot-4-importality/issues/9)

## 💽 Как установить

1. Установите его из [Библиотеки Ассетов Godot](https://godotengine.org/asset-library/asset/2025) или:
    - Склонируйте этот репозиторий или скачайте его содержимое в виде архива.
    - Поместите содержимое папки `addons` репозитория в папку `addons` вашего проекта.
1. Настройте параметры в `Editor Settings` -> `Importality`
    - [Укажите директорию для временных файлов](https://github.com/nklbdev/godot-4-importality/wiki/about-temporary-files-and-ram_drives-(ru)).
    - Укажите команду и её параметры для запуска вашего редактора в режиме экспорта данных, если это необходимо. Как настроить параметры для вашего графического приложения читайте в соответствующей статье [вики](https://github.com/nklbdev/godot-4-importality/wiki), посвящённой ему.

## 👷 Как использовать

**Обязательно прочитайте статью на вики про редактор, который вы используете! В этих статьях описаны важные нюансы настройки интеграции!**
- [Aseprite/LibreSprite](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-aseprite-(ru)) (Важно)
- [Krita](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-krita-(ru)) (Критически важно!)
- [Pencil2D](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-pencil_2d-(ru)) (Важно)
- [Piskel](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-piskel-(ru)) (Интеграции с приложением нет. Используется собственный парсер исходных файлов)
- [Pixelorama](https://github.com/nklbdev/godot-4-importality/wiki/exporting-data-from-pixelorama-(ru)) (Интеграции с приложением нет. Используется собственный парсер исходных файлов)
- [Другие графические форматы](https://github.com/nklbdev/godot-4-importality/wiki/importing-as-regular-images-(ru)) (Важно!)

Затем:

1. Сохраните файлы вашего любимого редактора в папку проекта Godot.
1. Выберите их в дереве файловой системы Godot. Скорее всего они уже импортированы как ресурс `Texture2D`.
1. Выберите нужный вам вариант импорта на панели "Import".
1. Настройте его параметры.
1. Если нужно, сохраните ваш вариант настройки параметров как пресет по умолчанию.
1. Нажмите кнопку "Reimport" (может понадобиться перезапуск движка).
1. В дальнейшем при изменении исходных файлов Godot автоматически повторит импорт.

## 💪 Как помочь проекту

Если вы знаете, как устроен еще один формат, или как работать с CLI очередного приложения, графику и анимацию из которого можно импортировать подобным образом - пожалуйста, предложите свою помощь в любом виде. Это может быть:

- [Тикет](https://github.com/nklbdev/godot-4-importality/issues) с описанием ошибки, проблемы или варианта улучшения дополнения. (Пожалуйста, приложите скриншоты и другие данные, которые помогут воспроизвести вашу проблему.)
- Текстовое описание формата или работы с CLI.
- [Пулл-реквест](https://github.com/nklbdev/godot-4-importality/pulls) с новым экспортером.
- Временная или постоянная лицензия на платное ПО для возможности изучить его и создать экспортер. Например для:
    - [Adobe Photoshop](https://www.adobe.com/products/photoshop.html)
    - [Adobe Animate](https://www.adobe.com/products/animate.html)
    - [Adobe Character Animator](https://www.adobe.com/products/character-animator.html)
    - [Affinity Photo](https://affinity.serif.com/photo)
    - [Moho Debut](https://moho.lostmarble.com/products/moho-debut) / [Moho Pro](https://moho.lostmarble.com/products/moho-pro)
    - [Toon Boom Harmony](https://www.toonboom.com/products/harmony)
    - [PyxelEdit](https://pyxeledit.com)
    - и других
