# Conway's Game of Life
![Play Store Screenshots](assets/bundle_android.jpg)
Conway's Game of Life app that focuses on UI and optimisation.
> This app uses default principles of Conway's Game of Life, go check them out on [Wikipedia](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life).

[![PlayStore](assets/PlayStoreButton.png)](https://play.google.com/store/apps/details?id=page.puzzak.gol)[![GitHub](assets/GHButton.png)](https://github.com/Puzzaks/gol/releases)
### Features
 - Customizability
 - Optimization
 - Adaptibility
 - Colorfulness
 - Interactivity

#### Customizability
The app is built to allow users change cell display in any way they want: add or remove borders between cells, make corners of the cells rounded and change colors of both live and dead cells. Users also can select delay between grid updates, thus allowing for speed controls.
#### Optimization
The app is optimised to run well on any device, with option to scale down cells to make a larger grid (which is a resource-heavy task to render). It has separate generator, that generates grid on-demand as a two-dimentional array of dead or alive cells. It allows for on-the-fly changes of grid size.
Generated frames are not displayed as an image, rather are drawn on a grid that allows for interactions and easy cell style adjustments. Generation runs as a asynchronous process which allows UI to be lag-free and to apply visual changes very fast.
#### Adaptibility
App can run on Android, ChromeOS, Windows and any other supported by Flutter platform. Platforms like web are not tested, but anyone can use this repository to build it on any platform. The app works fine with both touch controls and mouse.
#### Colorfulness
If the device supports custom theming (Android 12+ and latest Chrome OS), then you can select to color cells using device accent colors and UI inherits theme and color of the device to make experiense seamless.
#### Interactivity
Using mouse pointer or touch controls, users can "draw" on a grid, selecing cells to change their state. This allows for possibilities to draw something as a pixel art and make patterns, such as spaceships and oscillators.
### More screenshots
![Play Store Screenshots](assets/bundle_chrome.jpg)
![Play Store Screenshots](assets/bundle_tablet.jpg)
