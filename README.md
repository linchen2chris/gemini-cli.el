# gemini-cli.el

An Emacs interface for [Gemini CLI](https://blog.google/technology/developers/introducing-gemini-cli-open-source-ai-agent/), providing integration between Emacs and Gemini AI for coding assistance.

## Features

- Start, stop, and toggle Gemini Cli sessions directly from Emacs
- Support for multiple Gemini instances across different projects and directories
- Send commands to Gemini with or without file/line context
- Quick access to all Gemini slash commands via transient menus
- Customizable key bindings and appearance settings

## Installation

### Prerequisites

- Emacs 30.0 or higher
- [Gemini Code CLI](https://github.com/anthropics/gemini-cli) installed and configured
- Required Emacs packages: transient (0.4.0+), eat (0.9.2+)

### Using builtin use-package (Emacs 30+)

```elisp
(use-package gemini-cli :ensure t
  :vc (:url "https://github.com/linchen2chris/gemini-cli.el" :rev :newest)
  :config (gemini-cli-mode)
  :bind-keymap ("C-c c" . gemini-cli-command-map)) ;; or your preferred key
```

### Using straight.el

```elisp
(use-package gemini-cli
  :straight (:type git :host github :repo "linchen2chris/gemini-cli.el" :branch "main"
                   :files ("*.el" (:exclude "demo.gif")))
  :bind-keymap
  ("C-c c" . gemini-cli-command-map)
  :config
  (gemini-cli-mode))
```

## Usage

You need to set your own key binding for the Gemini Cli command map. The examples in this README use `C-c c` as the prefix key.

### Basic Commands

- `gemini-cli` (`C-c c c`) - Start Gemini. With prefix arg (`C-u`), switches to the Gemini buffer after creating. With double prefix (`C-u C-u`), continues previous conversation. With triple prefix (`C-u C-u C-u`), prompts for the project directory
- `gemini-cli-toggle` (`C-c c t`) - Toggle Gemini window
- `gemini-cli-switch-to-buffer` (`C-c c b`) - Switch to the Gemini buffer. With prefix arg (`C-u`), shows all Gemini instances across all directories
- `gemini-cli-kill` (`C-c c k`) - Kill Gemini session. With prefix arg (`C-u`), kills ALL Gemini instances across all directories
- `gemini-cli-send-command` (`C-c c s`) - Send command to Gemini
- `gemini-cli-send-command-with-context` (`C-c c x`) - Send command with current file and line context
- `gemini-cli-send-region` (`C-c c r`) - Send the current region or buffer to Gemini. With prefix arg (`C-u`), prompts for instructions to add to the text. With double prefix (`C-u C-u`), adds instructions and switches to Gemini buffer
- `gemini-cli-fix-error-at-point` (`C-c c e`) - Ask Gemini to fix the error at the current point (works with flycheck, flymake, and any system that implements help-at-pt)
- `gemini-cli-slash-commands` (`C-c c /`) - Access Gemini slash commands menu
- `gemini-cli-transient` (`C-c c m`) - Show all commands (transient menu)
- `gemini-cli-send-return` (`C-c c y`) - Send return key to Gemini (useful for confirming with Gemini without switching to the Gemini REPL buffer)
- `gemini-cli-send-escape` (`C-c c n`) - Send escape key to Gemini (useful for saying "No" when Gemini asks for confirmation without switching to the Gemini REPL buffer)
- `gemini-cli-fork` (`C-c c f`) - Fork conversation (jump to previous conversation by sending escape-escape to Gemini)
- `gemini-cli-send-1` (`C-c c 1`) - Send "1" to Gemini (useful for selecting the first option when Gemini presents a numbered menu)
- `gemini-cli-send-2` (`C-c c 2`) - Send "2" to Gemini (useful for selecting the second option when Gemini presents a numbered menu)
- `gemini-cli-send-3` (`C-c c 3`) - Send "3" to Gemini (useful for selecting the third option when Gemini presents a numbered menu)
- `gemini-cli-cycle-mode` (`C-c c TAB`) - Send Shift-Tab to Gemini to cycle between default mode, auto-accept edits mode, and plan mode

With a single prefix arg, `gemini-cli`, `gemini-cli-send-command` and
`gemini-cli-send-command-with-context` will switch to the Gemini terminal buffer after sending the
command.



### Read-Only Mode Toggle

The `gemini-cli-toggle-read-only-mode` command provides a convenient way to switch between normal terminal mode and read-only mode in the Gemini buffer:

- `gemini-cli-toggle-read-only-mode` - Toggle between read-only mode and normal mode

In read-only mode, you can interact with the terminal buffer just like a regular Emacs buffer, making it easy to select and copy text. However, you cannot change the buffer contents or enter Gemini commands in this mode. This is particularly useful when you need to copy output from Gemini without accidentally modifying the terminal.

The command automatically detects the current mode and switches to the other:
- If in normal terminal mode (semi-char mode), it switches to read-only mode
- If in read-only mode (emacs mode), it switches back to normal terminal mode

### Continuing Previous Conversations

The `gemini-cli` command supports continuing previous conversations using Gemini's `--continue`
flag:

- Double prefix arg (`C-u C-u C-c c c`) - Start Gemini and continue previous conversation

This allows you to resume where you left off in your previous Gemini session.

### Transient Menus

Access all commands through the transient menu with `C-c c m`.

#### Slash Commands Menu

For quick access to Gemini slash commands like `/help`, `/clear`, or `/compact`, use `C-c c /` to open the slash commands menu.

### Read-Only Mode for Text Selection

In the Gemini terminal, you can switch to a read-only mode to select and copy text:

- `C-c C-e` (`eat-emacs-mode`) - Switch to read-only mode with normal Emacs cursor for text selection
- `C-c C-j` (`semi-char-mode`) - Return to normal terminal mode

The cursor appearance in read-only mode can be customized via the `gemini-cli-read-only-mode-cursor-type` variable. This variable uses the format `(CURSOR-ON BLINKING-FREQUENCY CURSOR-OFF)`. For more information, run `M-x describe-variable RET gemini-cli-read-only-mode-cursor-type RET`.

```elisp
;; Customize cursor type in read-only mode (default is '(box nil nil))
;; Cursor type options: 'box, 'hollow, 'bar, 'hbar, or nil
(setq gemini-cli-read-only-mode-cursor-type '(bar nil nil))
```

### Multiple Gemini Instances

`gemini-cli.el` supports running multiple Gemini instances across different projects and directories. Each Gemini instance is associated with a specific directory (project root, file directory, or current directory).

#### Instance Management

- When you start Gemini with `gemini-cli`, it creates an instance for the current directory
- If a Gemini instance already exists for the directory, you'll be prompted to name the new instance (e.g., "tests", "docs")
- Buffer names follow the format:
  - `*gemini:/path/to/directory*` for the default instance
  - `*gemini:/path/to/directory:instance-name*` for named instances (e.g., `*gemini:/home/user/project:tests*`)
- If you're in a directory without a Gemini instance but have instances running in other directories, you'll be prompted to select one
- Your selection is remembered for that directory, so you won't be prompted again
- To start a new instance instead of selecting an existing one, cancel the prompt with `C-g`

#### Instance Selection

Commands that operate on an instance (`gemini-send-command`, `gemini-cli-switch-to-buffer`, `gemini-cli-kill`, etc.) will prompt you for the Gemini instance if there is more than one instance associated with the current buffer's project.

If the buffer file is not associated with a running Gemini instance, you can select an instance running in a different project. This is useful when you want Gemini to analyze dependent projects or files that you have checked out in sibling directories.

Gemini-cli.el remembers which buffers are associated with which Gemini instances, so you won't be repeatedly prompted. This association also helps gemini-cli.el "do the right thing" when killing a Gemini process and deleting its associated buffer.

#### Multiple Instances Per Directory

You can run multiple Gemini instances for the same directory to support different workflows:

- The first instance in a directory is the "default" instance
- Additional instances require a name when created (e.g., "tests", "docs", "refactor")
- When multiple instances exist for a directory, commands that interact with Gemini will prompt you to select which instance to use
- Use `C-u gemini-cli-switch-to-buffer` to see all Gemini instances across all directories (not just the current directory)

This allows you to have separate Gemini conversations for different aspects of your work within the same project, such as one instance for writing cli and another for writing tests.

## Customization

```elisp
;; Set your key binding for the command map
(global-set-key (kbd "C-c C-a") gemini-cli-command-map)

;; Set terminal type for the Gemini terminal emulation (default is "xterm-256color")
;; This determines terminal capabilities like color support
;; See the documentation for eat-term-name for more information
(setq gemini-cli-term-name "xterm-256color")

;; Change the path to the Gemini executable (default is "gemini")
;; Useful if Gemini is not in your PATH or you want to use a specific version
(setq gemini-cli-program "/usr/local/bin/gemini")

;; Set command line arguments for Gemini
;; For example, to enable verbose output
(setq gemini-cli-program-switches '("--verbose"))

;; Add hooks to run after Gemini is started
(add-hook 'gemini-cli-start-hook 'my-gemini-setup-function)

;; Adjust initialization delay (default is 0.1 seconds)
;; This helps prevent terminal layout issues if the buffer is displayed before Gemini is fully ready
(setq gemini-cli-startup-delay 0.2)

;; Configure the buffer size threshold for confirmation prompt (default is 100000 characters)
;; If a buffer is larger than this threshold, gemini-cli-send-region will ask for confirmation
;; before sending the entire buffer to Gemini
(setq gemini-cli-large-buffer-threshold 100000)

;; Disable truncation of Gemini output buffer (default is nil)
;; When set to t, gemini-cli.el can output display content without truncation
;; This is useful when working with large Gemini buffers
(setq gemini-cli-never-truncate-gemini-buffer t)
```

### Customizing Window Position

You can control how the Gemini Cli window appears using Emacs' `display-buffer-alist`. For example, to make the Gemini window appear in a persistent side window on the right side of your screen with 33% width:

```elisp
(add-to-list 'display-buffer-alist
                 `("^\\*gemini"
                   (display-buffer-in-side-window)
                   (side . right)
                   (window-width . ,width)
                   (window-parameters . ((no-delete-other-windows . t)))))
```

This layout works best on wide screens.

### Font Configuration for Better Rendering

Using a font with good Unicode support helps avoid flickering while Gemini Cli is rendering its thinking icons. [JuliaMono](https://juliamono.netlify.app/) has excellent Unicode symbols support. To let the Gemini Cli buffer use Julia Mono for rendering Unicode characters while still using your default font for ASCII characters add this elisp code:

```elisp
(setq use-default-font-for-symbols nil)
(set-fontset-font t 'unicode (font-spec :family "JuliaMono"))
```

If instead you want to use a particular font just for the Gemini Cli REPL but use a different font
everywhere else you can customize the `gemini-cli-repl-face`:

```elisp
(custom-set-faces
   '(gemini-cli-repl-face ((t (:family "JuliaMono")))))
```

#### Using Your 

### Reducing Flickering on Window Configuration Changes

To reduce flickering in the Gemini buffer on window configuration changes, you can adjust eat latency variables in a hook. This reduces flickering at the cost of some increased latency:

```elisp
  ;; reduce flickering
  (add-hook 'gemini-cli-start-hook
            (lambda ()
              (setq-local eat-minimum-latency 0.033
                          eat-maximum-latency 0.1)))
```

_Note_: Recent changes to gemini-cli.el have fixed flickering issues, making customization of these latency values less necessary. 

## Demo

### GIF Demo

![Gemini Cli Emacs Demo](./demo.gif)

This [demo](./demo.gif) shows gemini-cli.el in action, including accessing the transient menu, sending commands with file context, and fixing errors.

### Video Demo

[![The Emacs Gemini Cli Package](https://img.youtube.com/vi/K8sCVLmFyyU/0.jpg)](https://www.youtube.com/watch?v=K8sCVLmFyyU)

Check out this [video demo](https://www.youtube.com/watch?v=K8sCVLmFyyU) demonstrating the gemini-cli.el package. This video was kindly created and shared by a user of the package.

## Limitations

- `gemini-cli.el` only supports using [eat](https://codeberg.org/akib/emacs-eat) for the Gemini Cli terminal window. Eat provides better rendering with less flickering and visual artifacts compared to other terminal emulators like ansi-term and vterm in testing.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.
