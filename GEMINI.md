# Gemini CLI Development Guide

## Build and Test Commands
- Install package: `M-x package-install-file RET /path/to/gemini-cli.el`
- Use project Makefile targets (preferred methods):
  - Byte compile: `make compile`
  - Lint with checkdoc: `make checkdoc`
  - Run both checkdoc and compile: `make all`
- Alternative direct commands:
  - Byte compile: `emacs -Q --batch -f batch-byte-compile gemini-cli.el`
  - Check package: `emacs -Q --batch -l package-lint.el -f package-lint-batch-and-exit gemini-cli.el`
  - Lint with checkdoc: `emacs -Q --batch -l checkdoc -f checkdoc-file gemini-cli.el`

## Code Style Guidelines
- Prefix all functions/variables with `gemini-cli-` (public) or `gemini-cli--` (private)
- Follow standard Emacs Lisp naming conventions (kebab-case)
- Use lexical binding (include `lexical-binding: t` in header)
- Organize with section headers: `;;;; Section Name`
- Maintain proper package headers and autoload declarations
- Docstring for all functions and variables
  - Add a blank line after the first line of docstrings for multi-line descriptions
  - First line should be a complete sentence ending with a period
- Maintain dependency requirements: Emacs 30.1+, transient 0.4.0+, eat 0.8+

## Error Handling
- Use `if-let` for conditional execution with potential null values
- Provide clear error messages with `error` function
- Check for running Gemini instance before sending commands

## Project Structure
- Single file package with clear module organization
- Licensed under Apache License 2.0
