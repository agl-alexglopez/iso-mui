# Isometric MUI

This project aims to display mazes in various ways that allow the user to use and interact with their building and solving. This program experiments with isometric pixel art and offers a user interface for experimenting with mazes. So, it's an isometric maze user interface (iso-mui).

## Requirements

Zig is not yet version 1.0 so this project will likely break in the future. Right now it is on Zig version `0.15.1`. 

## Usage

This program lets you observe maze building and solving algorithms. Upon startup an arbitrary algorithm is playing.

- Adjust the generator you wish to see with the dropdown menu.
- Adjust the solver you wish to see with the dropdown menu.
- Restart the process once your desired algorithms are selected.

While playing, there are options to control how the algorithms run.

- Play the algorithm in reverse.
- Pause the algorithm.
- Play the algorithms forward.
- Slow down the algorithm steps.
- Speed up the algorithm steps.

There are default maze and window sizes provided. Custom maze and window dimensions can be passed on the command line.

```zsh
zig build run -- -r=20 -c=20 -w=720 -h=720
```

- The `-r=` flag controls the number of rows for the maze in squares.
- The `-c=` flag controls the number of columns for the maze in squares.
- The `-w=` flag controls the width of the window in pixels.
- The `-h=` flag controls the height of the window in pixels.

Because the maze is drawn in isometric pixel art, the provided maze row and column dimensions are automatically adjusted to be `NxN` where `N` is the larger of the arguments provided.

## Why

This is a "[Rosetta Stone](https://agl-alexglopez.github.io/2025/08/01/rosetta-stones-and-mazes-the-premise.html)" program that helped me learn the Zig programming language. For more on what a "[Rosetta Stone](https://agl-alexglopez.github.io/2025/08/01/rosetta-stones-and-mazes-the-premise.html)" program is, and how you can create something similar, visit my [blog](https://agl-alexglopez.github.io/).

There are more features that can be added in the future. Notably, there is a large number of maze generator algorithms I am aware of but have not implemented yet. Also, the solvers can be multi-threaded to further explore Zig's concurrency primitives. Keep an eye out for these updates, if interested.
