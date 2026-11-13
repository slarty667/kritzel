Kritzel 1.0
===========

A lightweight Skitch replacement for macOS. Annotate images from the
clipboard, add text, pixelate, crop -- and hand them on via the clipboard
or as a file.

Requirements: a Mac with Apple Silicon, macOS 13 or later.
The app speaks English and German and follows the system language.

Deutsche Anleitung: LIESMICH.txt


INSTALLATION (two steps)
------------------------

1. Drag Kritzel.app into the "Applications" folder.

2. Once, in Terminal (Applications > Utilities > Terminal):

      xattr -dr com.apple.quarantine /Applications/Kritzel.app

   After that the app starts normally with a double click.


WHY THE SECOND STEP?
--------------------

The app is built privately and not registered with Apple. macOS puts a
quarantine flag on everything that arrives from the internet or by mail and
then refuses to launch it with "developer cannot be verified". The command
removes that flag for this one app.

If you would rather not: the source code is included, and a Kritzel.app you
build yourself never has the problem (see below).


USAGE
-----

The normal case: copy an image anywhere, start Kritzel -- it is already on
the canvas. If the clipboard is empty, you get a blank white canvas.

  1 to 9        pick a tool: Select, Arrow, Rectangle, Ellipse, Text, Pen,
                Highlighter, Pixelate, Crop
  Cmd V         image from the clipboard into a new window
  Cmd Shift 4   capture a screen selection and open it
  Cmd N         blank canvas
  Cmd O         open an image file (drag and drop onto the window works too)
  Cmd S         save as PNG or JPEG
  Cmd Shift C   finished image to the clipboard
  Cmd Z         undo, Cmd Shift Z redo
  Delete        delete the selected object
  Arrow keys    nudge the selection by 1 pixel, with Shift by 10
  Shift drag    arrow in 45 degree steps, rectangle as a square
  Cmd Option I  resize the image
  Cmd + / -     zoom in / out (pinch or Cmd + scroll works too)
  Cmd 0         fit the image to the window
  Cmd 1         100%; in a zoomed image, scrolling pans the view

Objects stay vectors: click, move, drag the handles, change colour and
width afterwards, retype text with a double click. They are only burned in
when you save or copy.

Retina screenshots are handled as 2x images: tool sizes look the same as
on ordinary images, and saved files keep full resolution and appear at
their original size in other apps.

Crop works like in Skitch: the frame starts on the whole image, eight grips
adjust it, dragging inside moves it, and the bar shows the pixel dimensions
for typing. Return applies, Escape cancels.


BUILD IT YOURSELF (optional)
----------------------------

The "Source" folder holds everything the app is made of. All you need are
Apple's Command Line Tools, not Xcode:

      xcode-select --install
      cd Source
      ./build.sh
      cp -R Kritzel.app /Applications/

A Kritzel.app you build yourself does not need the xattr command above.
./run-tests.sh runs the test suite.


No warranty, no support, have fun.
