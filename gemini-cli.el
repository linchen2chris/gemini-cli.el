;;; gemini-cli.el --- Gemini CLI Emacs integration -*- lexical-binding: t; -*-

;; Author: Stephen Molitor <stevemolitor@gmail.com>
;; Version: 0.2.0
;; Package-Requires: ((emacs "30.0") (transient "0.9.3"))
;; Keywords: tools, ai
;; URL: https://github.com/stevemolitor/gemini-cli.el

;;; Commentary:
;; An Emacs interface to Gemini CLI.  This package provides convenient
;; ways to interact with Gemini from within Emacs, including sending
;; commands, toggling the Gemini window, and accessing slash commands.

;;; Code:

(require 'transient)
(require 'project)
(require 'cl-lib)

;;;; Customization options
(defgroup gemini-cli nil
  "Gemini AI interface for Emacs."
  :group 'tools)

(defgroup gemini-cli-eat nil
  "Eat terminal backend specific settings for Gemini CLI."
  :group 'gemini-cli)

(defgroup gemini-cli-vterm nil
  "Vterm terminal backend specific settings for Gemini CLI."
  :group 'gemini-cli)

(defgroup gemini-cli-window nil
  "Window management settings for Gemini CLI."
  :group 'gemini-cli)

(defface gemini-cli-repl-face
  nil
  "Face for Gemini REPL."
  :group 'gemini-cli)

(defcustom gemini-cli-term-name "xterm-256color"
  "Terminal type to use for Gemini REPL."
  :type 'string
  :group 'gemini-cli)

(defcustom gemini-cli-start-hook nil
  "Hook run after Gemini is started."
  :type 'hook
  :group 'gemini-cli)

(defcustom gemini-cli-startup-delay 0.1
  "Delay in seconds after starting Gemini before displaying buffer.

This helps fix terminal layout issues that can occur if the buffer
is displayed before Gemini is fully initialized."
  :type 'number
  :group 'gemini-cli)

(defcustom gemini-cli-large-buffer-threshold 100000
  "Size threshold in characters above which buffers are considered \"large\".

When sending a buffer to Gemini with `gemini-cli-send-region` and no
region is active, prompt for confirmation if buffer size exceeds this value."
  :type 'integer
  :group 'gemini-cli)

(defcustom gemini-cli-program "gemini"
  "Program to run when starting Gemini.
This is passed as the PROGRAM parameter to `eat-make`."
  :type 'string
  :group 'gemini-cli)

(defcustom gemini-cli-program-switches nil
  "List of command line switches to pass to the Gemini program.
These are passed as SWITCHES parameters to `eat-make`."
  :type '(repeat string)
  :group 'gemini-cli)

(defcustom gemini-cli-newline-keybinding-style 'newline-on-shift-return
  "Key binding style for entering newlines and sending messages.

This controls how the return key and its modifiers behave in Gemini buffers:
- \\='newline-on-shift-return: S-return enters a line break, RET sends the
  command (default)
- \\='newline-on-alt-return: M-return enters a line break, RET sends the command
- \\='shift-return-to-send: RET enters a line break, S-return sends the command
- \\='super-return-to-send: RET enters a line break, s-return sends the command

`\"S\"' is the shift key.
`\"s\"' is the hyper key, which is the COMMAND key on macOS."
  :type '(choice (const :tag "Newline on shift-return (s-return for newline, RET to send)" newline-on-shift-return)
                 (const :tag "Newline on alt-return (M-return for newline, RET to send)" newline-on-alt-return)
                 (const :tag "Shift-return to send (RET for newline, S-return to send)" shift-return-to-send)
                 (const :tag "Super-return to send (RET for newline, s-return to send)" super-return-to-send))
  :group 'gemini-cli)

(defcustom gemini-cli-enable-notifications t
  "Whether to show notifications when Gemini finishes and awaits input."
  :type 'boolean
  :group 'gemini-cli)

(defcustom gemini-cli-notification-function 'gemini-cli-default-notification
  "Function to call for notifications.

The function is called with two arguments:
- TITLE: Title of the notification
- MESSAGE: Body of the notification

You can set this to your own custom notification function.
The default function displays a message and pulses the modeline
to provide visual feedback when Gemini is ready for input."
  :type 'function
  :group 'gemini-cli)

(defcustom gemini-cli-confirm-kill t
  "Whether to ask for confirmation before killing Gemini instances.

When non-nil, gemini-cli-kill will prompt for confirmation.
When nil, Gemini instances will be killed without confirmation."
  :type 'boolean
  :group 'gemini-cli)

(defcustom gemini-cli-optimize-window-resize t
  "Whether to optimize terminal window resizing to prevent unnecessary reflows.

When non-nil, terminal reflows are only triggered when the window width
changes, not when only the height changes. This prevents unnecessary
terminal redraws when windows are split or resized vertically, improving
performance and reducing visual artifacts.

Set to nil if you experience issues with terminal display after window
resizing."
  :type 'boolean
  :group 'gemini-cli)

(defcustom gemini-cli-no-delete-other-windows nil
  "Whether to prevent Gemini CLI windows from being deleted.

When non-nil, gemini-cli will have the `no-delete-other-windows'
parameter.  This parameter prevents the gemini-cli window from
closing when calling `delete-other-windows' or any command that would
launch a new full-screen buffer."
  :type 'boolean
  :group 'gemini-cli-window)

;;;;; Eat terminal customizations
;; Eat-specific terminal faces
(defface gemini-cli-eat-prompt-annotation-running-face
  '((t :inherit eat-shell-prompt-annotation-running))
  "Face for running prompt annotations in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-prompt-annotation-success-face
  '((t :inherit eat-shell-prompt-annotation-success))
  "Face for successful prompt annotations in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-prompt-annotation-failure-face
  '((t :inherit eat-shell-prompt-annotation-failure))
  "Face for failed prompt annotations in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-term-bold-face
  '((t :inherit eat-term-bold))
  "Face for bold text in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-term-faint-face
  '((t :inherit eat-term-faint))
  "Face for faint text in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-term-italic-face
  '((t :inherit eat-term-italic))
  "Face for italic text in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-term-slow-blink-face
  '((t :inherit eat-term-slow-blink))
  "Face for slow blinking text in Gemini eat terminal."
  :group 'gemini-cli-eat)

(defface gemini-cli-eat-term-fast-blink-face
  '((t :inherit eat-term-fast-blink))
  "Face for fast blinking text in Gemini eat terminal."
  :group 'gemini-cli-eat)

(dotimes (i 10)
  (let ((face-name (intern (format "gemini-cli-eat-term-font-%d-face" i)))
        (eat-face (intern (format "eat-term-font-%d" i))))
    (eval `(defface ,face-name
             '((t :inherit ,eat-face))
             ,(format "Face for font %d in Gemini eat terminal." i)
             :group 'gemini-cli-eat))))

(defcustom gemini-cli-eat-read-only-mode-cursor-type '(box nil nil)
  "Type of cursor to use as invisible cursor in Gemini CLI terminal buffer.

The value is a list of form (CURSOR-ON BLINKING-FREQUENCY CURSOR-OFF).

When the cursor is on, CURSOR-ON is used as `cursor-type', which see.
BLINKING-FREQUENCY is the blinking frequency of cursor's blinking.
When the cursor is off, CURSOR-OFF is used as `cursor-type'.  This
should be nil when cursor is not blinking.

Valid cursor types for CURSOR-ON and CURSOR-OFF:
- t: Frame default cursor
- box: Filled box cursor
- (box . N): Box cursor with specified size N
- hollow: Hollow cursor
- bar: Vertical bar cursor
- (bar . N): Vertical bar with specified height N
- hbar: Horizontal bar cursor
- (hbar . N): Horizontal bar with specified width N
- nil: No cursor

BLINKING-FREQUENCY can be nil (no blinking) or a number."
  :type '(list
          (choice
           (const :tag "Frame default" t)
           (const :tag "Filled box" box)
           (cons :tag "Box with specified size" (const box) integer)
           (const :tag "Hollow cursor" hollow)
           (const :tag "Vertical bar" bar)
           (cons :tag "Vertical bar with specified height" (const bar)
                 integer)
           (const :tag "Horizontal bar" hbar)
           (cons :tag "Horizontal bar with specified width"
                 (const hbar) integer)
           (const :tag "None" nil))
          (choice
           (const :tag "No blinking" nil)
           (number :tag "Blinking frequency"))
          (choice
           (const :tag "Frame default" t)
           (const :tag "Filled box" box)
           (cons :tag "Box with specified size" (const box) integer)
           (const :tag "Hollow cursor" hollow)
           (const :tag "Vertical bar" bar)
           (cons :tag "Vertical bar with specified height" (const bar)
                 integer)
           (const :tag "Horizontal bar" hbar)
           (cons :tag "Horizontal bar with specified width"
                 (const hbar) integer)
           (const :tag "None" nil)))
  :group 'gemini-cli-eat)

(defcustom gemini-cli-eat-never-truncate-gemini-buffer nil
  "When non-nil, disable truncation of Gemini output buffer.

By default, Eat will truncate the terminal scrollback buffer when it
reaches a certain size.  This can cause Gemini's output to be cut off
when dealing with large responses.  Setting this to non-nil disables
the scrollback size limit, allowing Gemini to output unlimited content
without truncation.

Note: Disabling truncation may consume more memory for very large
outputs."
  :type 'boolean
  :group 'gemini-cli-eat)

(make-obsolete-variable 'gemini-cli-eat-never-truncate-gemini-buffer
                        "Setting it to t can consume more memory for very large outputs and can cause performance issues with long Gemini sessions"
                        "0.4.0")

;;;;; Vterm terminal customizations
(defcustom gemini-cli-vterm-buffer-multiline-output t
  "Whether to buffer vterm output to prevent flickering on multi-line input.

When non-nil, vterm output that appears to be redrawing multi-line
input boxes will be buffered briefly and processed in a single
batch. This prevents the flickering that can occur when Gemini redraws
its input box as it expands to multiple lines.

This only affects the vterm backend."
  :type 'boolean
  :group 'gemini-cli-vterm)

(defcustom gemini-cli-vterm-multiline-delay 0.01
  "Delay in seconds before processing buffered vterm output.

This controls how long vterm waits to collect output before processing
it when `gemini-cli-vterm-buffer-multiline-output' is enabled.
The delay should be long enough to collect bursts of updates but short
enough to not be noticeable to the user.

The default value of 0.01 seconds (10ms) provides a good balance
between reducing flickering and maintaining responsiveness."
  :type 'number
  :group 'gemini-cli-vterm)

;;;; Forward declrations for flycheck
(declare-function flycheck-overlay-errors-at "flycheck")
(declare-function flycheck-error-filename "flycheck")
(declare-function flycheck-error-line "flycheck")
(declare-function flycheck-error-message "flycheck")

;;;; Internal state variables
(defvar gemini-cli--directory-buffer-map (make-hash-table :test 'equal)
  "Hash table mapping directories to user-selected Gemini buffers.
Keys are directory paths, values are buffer objects.
This allows remembering which Gemini instance the user selected
for each directory across multiple invocations.")

(defvar gemini-cli--window-widths nil
  "Hash table mapping windows to their last known widths for eat terminals.")

;;;; Key bindings
;;;###autoload (autoload 'gemini-cli-command-map "gemini-cli")
(defvar gemini-cli-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "/") 'gemini-cli-slash-commands)
    (define-key map (kbd "!") 'gemini-cli-send-shell)
    (define-key map (kbd "b") 'gemini-cli-switch-to-buffer)
    (define-key map (kbd "B") 'gemini-cli-select-buffer)
    (define-key map (kbd "c") 'gemini-cli)
    (define-key map (kbd "C") 'gemini-cli-continue)
    (define-key map (kbd "R") 'gemini-cli-resume)
    (define-key map (kbd "i") 'gemini-cli-new-instance)
    (define-key map (kbd "d") 'gemini-cli-start-in-directory)
    (define-key map (kbd "e") 'gemini-cli-fix-error-at-point)
    (define-key map (kbd "k") 'gemini-cli-kill)
    (define-key map (kbd "K") 'gemini-cli-kill-all)
    (define-key map (kbd "m") 'gemini-cli-transient)
    (define-key map (kbd "n") 'gemini-cli-send-escape)
    (define-key map (kbd "f") 'gemini-cli-fork)
    (define-key map (kbd "r") 'gemini-cli-send-region)
    (define-key map (kbd "s") 'gemini-cli-send-command)
    (define-key map (kbd "t") 'gemini-cli-toggle)
    (define-key map (kbd "x") 'gemini-cli-send-command-with-context)
    (define-key map (kbd "y") 'gemini-cli-send-return)
    (define-key map (kbd "z") 'gemini-cli-toggle-read-only-mode)
    (define-key map (kbd "1") 'gemini-cli-send-1)
    (define-key map (kbd "2") 'gemini-cli-send-2)
    (define-key map (kbd "3") 'gemini-cli-send-3)
    (define-key map (kbd "M") 'gemini-cli-cycle-mode)
    (define-key map (kbd "o") 'gemini-cli-send-buffer-file)
    map)
  "Keymap for Gemini commands.")

;;;; Transient Menus
;;;###autoload (autoload 'gemini-cli-transient "gemini-cli" nil t)
(transient-define-prefix gemini-cli-transient ()
  "Gemini command menu."
  ["Gemini Commands"
   ["Start/Stop Gemini"
    ("c" "Start Gemini" gemini-cli)
    ("d" "Start in directory" gemini-cli-start-in-directory)
    ("C" "Continue conversation" gemini-cli-continue)
    ("R" "Resume session" gemini-cli-resume)
    ("i" "New instance" gemini-cli-new-instance)
    ("k" "Kill Gemini" gemini-cli-kill)
    ("K" "Kill all Gemini instances" gemini-cli-kill-all)
    ]
   ["Send Commands to Gemini"
    ("s" "Send command" gemini-cli-send-command)
    ("x" "Send command with context" gemini-cli-send-command-with-context)
    ("r" "Send region or buffer" gemini-cli-send-region)
    ("o" "Send buffer file" gemini-cli-send-buffer-file)
    ("e" "Fix error at point" gemini-cli-fix-error-at-point)
    ("f" "Fork conversation" gemini-cli-fork)
    ("/" "Slash Commands" gemini-cli-slash-commands)]
   ["Manage Gemini"
    ("t" "Toggle gemini window" gemini-cli-toggle)
    ("b" "Switch to Gemini buffer" gemini-cli-switch-to-buffer)
    ("B" "Select from all Gemini buffers" gemini-cli-select-buffer)
    ("z" "Toggle read-only mode" gemini-cli-toggle-read-only-mode)
    ("M" "Cycle Gemini mode" gemini-cli-cycle-mode :transient t)
    ]
   ["Quick Responses"
    ("y" "Send <return>" gemini-cli-send-return)
    ("n" "Send <escape>" gemini-cli-send-escape)
    ("1" "Send \"1\"" gemini-cli-send-1)
    ("2" "Send \"2\"" gemini-cli-send-2)
    ("3" "Send \"3\"" gemini-cli-send-3)
    ]])

;;;###autoload (autoload 'gemini-cli-slash-commands "gemini-cli" nil t)
(transient-define-prefix gemini-cli-slash-commands ()
  "Gemini slash commands menu."
  ["Slash Commands"
   ["Basic Commands"
    ("b" "Bug" (lambda () (interactive) (gemini-cli--do-send-command "/bug")))
    ("c" "Clear" (lambda () (interactive) (gemini-cli--do-send-command "/clear")))
    ("d" "Docs" (lambda () (interactive) (gemini-cli--do-send-command "/docs")))
    ("e" "Extensions" (lambda () (interactive) (gemini-cli--do-send-command "/extensions")))
    ("m" "Mcp" (lambda () (interactive) (gemini-cli--do-send-command "/mcp")))
    ("o" "Compress" (lambda () (interactive) (gemini-cli--do-send-command "/compress")))
    ("p" "Privacy" (lambda () (interactive) (gemini-cli--do-send-command "/Privacy")))
    ("t" "Tools" (lambda () (interactive) (gemini-cli--do-send-command "/tools")))
    ("q" "Quit" (lambda () (interactive) (gemini-cli--do-send-command "/quit")))
    ("h" "Help" (lambda () (interactive) (gemini-cli--do-send-command "/help")))]

   ["Special Commands"
    ("l" "Chat List" (lambda () (interactive) (gemini-cli--do-send-command "/chat list")))
    ("s" "Chat Save" (lambda () (interactive) (gemini-cli--do-send-command "/chat save")))
    ("r" "Chat Resume" (lambda () (interactive) (gemini-cli--do-send-command "/chat resume")))
    ("w" "Memory Show" (lambda () (interactive) (gemini-cli--do-send-command "/memory show")))
    ("a" "Memory Add" (lambda () (interactive) (gemini-cli--do-send-command "/memory add")))
    ("f" "Memory Refresh" (lambda () (interactive) (gemini-cli--do-send-command "/memory refresh")))]

   ["Additional Commands"
    ("!" "Shell" (lambda () (interactive) (call-interactively 'gemini-cli-send-shell)))
    ("@" "Add Context" (lambda () (interactive) (gemini-cli--do-send-command "@")))]
   ])

;;;; Terminal abstraction layer
;; This layer abstracts terminal operations to support multiple backends (eat, vterm, etc.)

(require 'cl-lib)

(defcustom gemini-cli-terminal-backend 'eat
  "Terminal backend to use for Gemini CLI.
Choose between \\='eat (default) and \\='vterm terminal emulators."
  :type '(radio (const :tag "Eat terminal emulator" eat)
                (const :tag "Vterm terminal emulator" vterm))
  :group 'gemini-cli)

;;;;; Generic function definitions

(cl-defgeneric gemini-cli--term-make (backend buffer-name program &optional switches)
  "Create a terminal using BACKEND in BUFFER-NAME running PROGRAM.
Optional SWITCHES are command-line arguments to PROGRAM.
Returns the buffer containing the terminal.")

(cl-defgeneric gemini-cli--term-send-string (backend terminal string)
  "Send STRING to TERMINAL using BACKEND.")

(cl-defgeneric gemini-cli--term-kill-process (backend buffer)
  "Kill the terminal process in BUFFER using BACKEND.")

(cl-defgeneric gemini-cli--term-read-only-mode (backend)
  "Switch current terminal to read-only mode using BACKEND.")

(cl-defgeneric gemini-cli--term-interactive-mode (backend)
  "Switch current terminal to interactive mode using BACKEND.")

(cl-defgeneric gemini-cli--term-in-read-only-p (backend)
  "Check if current terminal is in read-only mode using BACKEND.")

(cl-defgeneric gemini-cli--term-configure (backend)
  "Configure terminal in current buffer with BACKEND specific settings.")

(cl-defgeneric gemini-cli--term-customize-faces (backend)
  "Apply face customizations for the terminal using BACKEND.")

(cl-defgeneric gemini-cli--term-setup-keymap (backend)
  "Set up the local keymap for Gemini CLI buffers using BACKEND.")

(cl-defgeneric gemini-cli--term-get-adjust-process-window-size-fn (backend)
  "Get the BACKEND specific function that adjusts window size.")

;;;;; eat backend implementations

;; Declare external variables and functions from eat package
(defvar eat--semi-char-mode)
(defvar eat--synchronize-scroll-function)
(defvar eat-invisible-cursor-type)
(defvar eat-term-name)
(defvar eat-terminal)
(declare-function eat--adjust-process-window-size "eat" (&rest args))
(declare-function eat--set-cursor "eat" (terminal &rest args))
(declare-function eat-emacs-mode "eat")
(declare-function eat-kill-process "eat" (&optional buffer))
(declare-function eat-make "eat" (name program &optional startfile &rest switches))
(declare-function eat-semi-char-mode "eat")
(declare-function eat-term-display-beginning "eat" (terminal))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-live-p "eat" (terminal))
(declare-function eat-term-parameter "eat" (terminal parameter) t)
(declare-function eat-term-redisplay "eat" (terminal))
(declare-function eat-term-reset "eat" (terminal))
(declare-function eat-term-send-string "eat" (terminal string))

;; Helper to ensure eat is loaded
(defun gemini-cli--ensure-eat ()
  "Ensure eat package is loaded."
  (unless (featurep 'eat)
    (unless (require 'eat nil t)
      (error "The eat package is required for eat terminal backend. Please install it"))))

(cl-defmethod gemini-cli--term-make ((_backend (eql eat)) buffer-name program &optional switches)
  "Create an eat terminal for BACKEND.

_BACKEND is the terminal backend type (should be \\='eat).
BUFFER-NAME is the name for the new terminal buffer.
PROGRAM is the program to run in the terminal.
SWITCHES are optional command-line arguments for PROGRAM."
  (gemini-cli--ensure-eat)

  (let* ((trimmed-buffer-name (string-trim-right (string-trim buffer-name "\\*") "\\*")))
    (apply #'eat-make trimmed-buffer-name program nil switches)))

(cl-defmethod gemini-cli--term-send-string ((_backend (eql eat)) string)
  "Send STRING to eat terminal.

_BACKEND is the terminal backend type (should be \\='eat).
STRING is the text to send to the terminal."
  (eat-term-send-string eat-terminal string))

(cl-defmethod gemini-cli--term-kill-process ((_backend (eql eat)) buffer)
  "Kill the eat terminal process in BUFFER.

_BACKEND is the terminal backend type (should be \\='eat).
BUFFER is the terminal buffer containing the process to kill."
  (with-current-buffer buffer
    (eat-kill-process)
    (kill-buffer buffer)))

(cl-defmethod gemini-cli--term-read-only-mode ((_backend (eql eat)))
  "Switch eat terminal to read-only mode.

_BACKEND is the terminal backend type (should be \\'eat)."
  (gemini-cli--ensure-eat)
  (eat-emacs-mode)
  (setq-local eat-invisible-cursor-type gemini-cli-eat-read-only-mode-cursor-type)
  (eat--set-cursor nil :invisible))

(cl-defmethod gemini-cli--term-interactive-mode ((_backend (eql eat)))
  "Switch eat terminal to interactive mode.

_BACKEND is the terminal backend type (should be \\='eat)."
  (gemini-cli--ensure-eat)
  (eat-semi-char-mode)
  (setq-local eat-invisible-cursor-type nil)
  (eat--set-cursor nil :invisible))

(cl-defmethod gemini-cli--term-in-read-only-p ((_backend (eql eat)))
  "Check if eat terminal is in read-only mode.

_BACKEND is the terminal backend type (should be \\='eat)."
  (not eat--semi-char-mode))

(defun gemini-cli--eat-synchronize-scroll (windows)
  "Synchronize scrolling and point between terminal and WINDOWS.

WINDOWS is a list of windows.  WINDOWS may also contain the special
symbol `buffer', in which case the point of current buffer is set.

This custom version keeps the prompt at the bottom of the window when
possible, preventing the scrolling up issue when editing other buffers."
  (dolist (window windows)
    (if (eq window 'buffer)
        (goto-char (eat-term-display-cursor eat-terminal))
      ;; Don't move the cursor around when in eat-emacs-mode
      (when (not buffer-read-only)
        (let ((cursor-pos (eat-term-display-cursor eat-terminal)))
          ;; Always set point to cursor position
          (set-window-point window cursor-pos)
          ;; Try to keep cursor visible with minimal scrolling
          (cond
           ;; If cursor is at/near end, keep at bottom
           ((>= cursor-pos (- (point-max) 2))
            (with-selected-window window
              (goto-char cursor-pos)
              (recenter -1)))
           ;; If cursor not visible, scroll minimally to show it
           ((not (pos-visible-in-window-p cursor-pos window))
            (with-selected-window window
              (goto-char cursor-pos)
              ;; Center cursor in window instead of jumping to term beginning
              (recenter)))))))))

(cl-defmethod gemini-cli--term-configure ((_backend (eql eat)))
  "Configure eat terminal in current buffer.

_BACKEND is the terminal backend type (should be \\='eat)."
  (gemini-cli--ensure-eat)
  ;; Configure eat-specific settings
  (setq-local eat-term-name gemini-cli-term-name)
  (setq-local eat-enable-directory-tracking nil)
  (setq-local eat-enable-shell-command-history nil)
  (setq-local eat-enable-shell-prompt-annotation nil)
  (when gemini-cli-eat-never-truncate-gemini-buffer
    (setq-local eat-term-scrollback-size nil))

  ;; Set up custom scroll function to stop eat from scrolling to the top
  (setq-local eat--synchronize-scroll-function #'gemini-cli--eat-synchronize-scroll)

  ;; Configure bell handler - ensure eat-terminal exists
  (when (bound-and-true-p eat-terminal)
    (eval '(setf (eat-term-parameter eat-terminal 'ring-bell-function) #'gemini-cli--notify)))

  ;; fix wonky initial terminal layout that happens sometimes if we show the buffer before gemini is ready
  (sleep-for gemini-cli-startup-delay))

(cl-defmethod gemini-cli--term-customize-faces ((_backend (eql eat)))
  "Apply face customizations for eat terminal.

_BACKEND is the terminal backend type (should be \\='eat)."
  ;; Remap eat faces to Gemini-specific faces
  (face-remap-add-relative 'eat-shell-prompt-annotation-running 'gemini-cli-eat-prompt-annotation-running-face)
  (face-remap-add-relative 'eat-shell-prompt-annotation-success 'gemini-cli-eat-prompt-annotation-success-face)
  (face-remap-add-relative 'eat-shell-prompt-annotation-failure 'gemini-cli-eat-prompt-annotation-failure-face)
  (face-remap-add-relative 'eat-term-bold 'gemini-cli-eat-term-bold-face)
  (face-remap-add-relative 'eat-term-faint 'gemini-cli-eat-term-faint-face)
  (face-remap-add-relative 'eat-term-italic 'gemini-cli-eat-term-italic-face)
  (face-remap-add-relative 'eat-term-slow-blink 'gemini-cli-eat-term-slow-blink-face)
  (face-remap-add-relative 'eat-term-fast-blink 'gemini-cli-eat-term-fast-blink-face)
  (dolist (i (number-sequence 0 9))
    (let ((eat-face (intern (format "eat-term-font-%d" i)))
          (gemini-face (intern (format "gemini-cli-eat-term-font-%d-face" i))))
      (face-remap-add-relative eat-face gemini-face))))

(cl-defmethod gemini-cli--term-setup-keymap ((_backend (eql eat)))
  "Set up the local keymap for Gemini CLI buffers.

_BACKEND is the terminal backend type (should be \\='eat)."
  (let ((map (make-sparse-keymap)))
    ;; Inherit parent eat keymap
    (set-keymap-parent map (current-local-map))

    ;; C-g for escape
    (define-key map (kbd "C-g") #'gemini-cli-send-escape)

    ;; Configure key bindings based on user preference
    (pcase gemini-cli-newline-keybinding-style
      ('newline-on-shift-return
       ;; S-return enters a line break, RET sends the command
       (define-key map (kbd "<S-return>") #'gemini-cli--eat-send-alt-return)
       (define-key map (kbd "<return>") #'gemini-cli--eat-send-return))
      ('newline-on-alt-return
       ;; M-return enters a line break, RET sends the command
       (define-key map (kbd "<M-return>") #'gemini-cli--eat-send-alt-return)
       (define-key map (kbd "<return>") #'gemini-cli--eat-send-return))
      ('shift-return-to-send
       ;; RET enters a line break, S-return sends the command
       (define-key map (kbd "<return>") #'gemini-cli--eat-send-alt-return)
       (define-key map (kbd "<S-return>") #'gemini-cli--eat-send-return))
      ('super-return-to-send
       ;; RET enters a line break, s-return sends the command.
       (define-key map (kbd "<return>") #'gemini-cli--eat-send-alt-return)
       (define-key map (kbd "<s-return>") #'gemini-cli--eat-send-return)))
    (use-local-map map)))

(defun gemini-cli--eat-send-alt-return ()
  "Send <alt>-<return> to eat."
  (interactive)
  (eat-term-send-string eat-terminal "\e\C-m"))

(defun gemini-cli--eat-send-return ()
  "Send <return> to eat."
  (interactive)
  (eat-term-send-string eat-terminal (kbd "RET")))

(cl-defgeneric gemini-cli--term-get-adjust-process-window-size-fn (backend)
  "Get the BACKEND specific function that adjusts window size.")

(cl-defmethod gemini-cli--term-get-adjust-process-window-size-fn ((_backend (eql eat)))
  "Get the BACKEND specific function that adjusts window size."
  #'eat--adjust-process-window-size)

;;;;; vterm backend implementations

;; Declare external variables and functions from vterm package
(defvar vterm-buffer-name)
(defvar vterm-copy-mode)
(defvar vterm-environment)
(defvar vterm-shell)
(defvar vterm-term-environment-variable)
(declare-function vterm "vterm" (&optional buffer-name))
(declare-function vterm--window-adjust-process-window-size "vterm" (process window))
(declare-function vterm-copy-mode "vterm" (&optional arg))
(declare-function vterm-mode "vterm")
(declare-function vterm-send-key "vterm" key &optional shift meta ctrl accept-proc-output)
(declare-function vterm-send-string "vterm" (string &optional paste-p))

;; Helper to ensure vterm is loaded
(cl-defmethod gemini-cli--term-make ((_backend (eql vterm)) buffer-name program &optional switches)
  "Create a vterm terminal.

_BACKEND is the terminal backend type (should be \\='vterm).
BUFFER-NAME is the name for the new terminal buffer.
PROGRAM is the program to run in the terminal.
SWITCHES are optional command-line arguments for PROGRAM."
  (gemini-cli--ensure-vterm)
  (let* ((vterm-shell (if switches
                          (concat program " " (mapconcat #'identity switches " "))
                        program))
         (buffer (get-buffer-create buffer-name)))
    (with-current-buffer buffer
      ;; vterm needs to have an open window before starting the gemini
      ;; process; otherwise Gemini doesn't seem to know how wide its
      ;; terminal window is and it draws the input box too wide. But
      ;; the user may not want to pop to the buffer. For some reason
      ;; `display-buffer' also leads to wonky results, it has to be
      ;; `pop-to-buffer'. So, show the buffer, start vterm-mode (which
      ;; starts the vterm-shell gemini process), and then hide the
      ;; buffer. We'll optionally re-open it later.
      ;;
      ;; [TODO] see if there's a cleaner way to do this.
      (pop-to-buffer buffer)
      (vterm-mode)
      (delete-window (get-buffer-window buffer))
      buffer)))

(defun gemini-cli--ensure-vterm ()
  "Ensure vterm package is loaded."
  (unless (featurep 'vterm)
    (unless (require 'vterm nil t)
      (error "The vterm package is required for vterm terminal backend. Please install it"))))

(cl-defmethod gemini-cli--term-send-string ((_backend (eql vterm)) string)
  "Send STRING to vterm terminal.

_BACKEND is the terminal backend type (should be \\='vterm).
_TERMINAL is unused for vterm backend.
STRING is the text to send to the terminal."
  (vterm-send-string string))

(cl-defmethod gemini-cli--term-kill-process ((_backend (eql vterm)) buffer)
  "Kill the vterm terminal process in BUFFER.

_BACKEND is the terminal backend type (should be \\='vterm).
BUFFER is the terminal buffer containing the process to kill."
  (kill-process (get-buffer-process buffer)))

;; Mode operations
(cl-defmethod gemini-cli--term-read-only-mode ((_backend (eql vterm)))
  "Switch vterm terminal to read-only mode.

_BACKEND is the terminal backend type (should be \\='vterm)."
  (gemini-cli--ensure-vterm)
  (vterm-copy-mode 1)
  (setq-local cursor-type t))

(cl-defmethod gemini-cli--term-interactive-mode ((_backend (eql vterm)))
  "Switch vterm terminal to interactive mode.

_BACKEND is the terminal backend type (should be \\='vterm)."
  (gemini-cli--ensure-vterm)
  (vterm-copy-mode -1)
  (setq-local cursor-type nil))

(cl-defmethod gemini-cli--term-in-read-only-p ((_backend (eql vterm)))
  "Check if vterm terminal is in read-only mode.

_BACKEND is the terminal backend type (should be \\='vterm)."
  vterm-copy-mode)

(cl-defmethod gemini-cli--term-configure ((_backend (eql vterm)))
  "Configure vterm terminal in current buffer.

_BACKEND is the terminal backend type (should be \\='vterm)."
  (gemini-cli--ensure-vterm)
  ;; set TERM
  (setq vterm-term-environment-variable gemini-cli-term-name)
  ;; Prevent vterm from automatically renaming the buffer
  (setq-local vterm-buffer-name-string nil)
  ;; Disable automatic scrolling to bottom on output to prevent flickering
  (setq-local vterm-scroll-to-bottom-on-output nil)
  ;; Disable immediate redraw to batch updates and reduce flickering
  (setq-local vterm--redraw-immididately nil)
  ;; Try to prevent cursor flickering by disabling Emacs' own cursor management
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)  ; Let vterm handle the cursor entirely
  ;; Set timer delay to nil for faster updates (reduces visible flicker duration)
  ;; (setq-local vterm-timer-delay nil)
  ;; Increase process read buffering to batch more updates together
  (when-let ((proc (get-buffer-process (current-buffer))))
    (set-process-query-on-exit-flag proc nil)
    ;; Try to make vterm read larger chunks at once
    (process-put proc 'read-output-max 4096))
  ;; Set up bell detection advice
  (advice-add 'vterm--filter :around #'gemini-cli--vterm-bell-detector)
  ;; Set up multi-line buffering to prevent flickering
  (advice-add 'vterm--filter :around #'gemini-cli--vterm-multiline-buffer-filter))

(cl-defmethod gemini-cli--term-customize-faces ((_backend (eql vterm)))
  "Apply face customizations for vterm terminal.

_BACKEND is the terminal backend type (should be \\='vterm)."
  ;; no faces to customize yet (this could change)
  )

(defun gemini-cli--vterm-send-escape ()
  "Send escape key to vterm."
  (interactive)
  (vterm-send-key ""))

(defun gemini-cli--vterm-send-return ()
  "Send escape key to vterm."
  (interactive)
  (vterm-send-key ""))

(defun gemini-cli--vterm-send-alt-return ()
  "Send <alt>-<return> to vterm."
  (interactive)
  (vterm-send-key "" nil t))

(defun gemini-cli--vterm-send-shift-return ()
  "Send shift return to vterm."
  (interactive)
  (vterm-send-key "" t))

(defun gemini-cli--vterm-send-super-return ()
  "Send escape key to vterm."
  (interactive)
  ;; (vterm-send-key " " t)
  (vterm-send-key (kbd "s-<return>") t))

;; (defun gemini-cli--vterm-send-alt-return ()
;;   "Send alt-return to vterm for newline without submitting."
;;   (message "gemini-cli--vterm-send-alt-return invoked")
;;   (interactive)
;;   (vterm-send-key "" nil t))

(cl-defmethod gemini-cli--term-setup-keymap ((_backend (eql vterm)))
  "Set up the local keymap for Gemini CLI buffers.

_BACKEND is the terminal backend type (should be \\='vterm)."
  (let ((map (make-sparse-keymap)))
    ;; Inherit parent eat keymap
    (set-keymap-parent map (current-local-map))

    ;; C-g for escape
    (define-key map (kbd "C-g") #'gemini-cli--vterm-send-escape)

    (pcase gemini-cli-newline-keybinding-style
      ('newline-on-shift-return
       ;; S-return enters a line break, RET sends the command
       (define-key map (kbd "<S-return>") #'gemini-cli--vterm-send-alt-return)
       (define-key map (kbd "<return>") #'gemini-cli--vterm-send-return))
      ('newline-on-alt-return
       ;; M-return enters a line break, RET sends the command
       (define-key map (kbd "<M-return>") #'gemini-cli--vterm-send-alt-return)
       (define-key map (kbd "<return>") #'gemini-cli--vterm-send-return))
      ('shift-return-to-send
       ;; RET enters a line break, S-return sends the command
       (define-key map (kbd "<return>") #'gemini-cli--vterm-send-alt-return)
       (define-key map (kbd "<S-return>") #'gemini-cli--vterm-send-return))
      ('super-return-to-send
       ;; RET enters a line break, s-return sends the command.
       (define-key map (kbd "<return>") #'gemini-cli--vterm-send-alt-return)
       (define-key map (kbd "<s-return>") #'gemini-cli--vterm-send-return)))

    (use-local-map map)))

(cl-defmethod gemini-cli--term-get-adjust-process-window-size-fn ((_backend (eql vterm)))
  "Get the BACKEND specific function that adjusts window size."
  #'vterm--window-adjust-process-window-size)

;;;; Private util functions
(defmacro gemini-cli--with-buffer (&rest body)
  "Execute BODY with the Gemini buffer, handling buffer selection and display.

Gets or prompts for the Gemini buffer, executes BODY within that buffer's
context, displays the buffer, and shows not-running message if no buffer
is found."
  `(if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
       (with-current-buffer gemini-cli-buffer
         ,@body
         (display-buffer gemini-cli-buffer))
     (gemini-cli--show-not-running-message)))

(defun gemini-cli--buffer-p (buffer)
  "Return non-nil if BUFFER is a Gemini buffer.

BUFFER can be either a buffer object or a buffer name string."
  (let ((name (if (stringp buffer)
                  buffer
                (buffer-name buffer))))
    (and name (string-match-p "^\\*gemini:" name))))

(defun gemini-cli--directory ()
  "Get get the root Gemini directory for the current buffer.

If not in a project and no buffer file return `default-directory'."
  (let* ((project (project-current))
         (current-file (buffer-file-name)))
    (cond
     ;; Case 1: In a project
     (project (project-root project))
     ;; Case 2: Has buffer file (when not in VC repo)
     (current-file (file-name-directory current-file))
     ;; Case 3: No project and no buffer file
     (t default-directory))))

(defun gemini-cli--find-all-gemini-buffers ()
  "Find all active Gemini buffers across all directories.

Returns a list of buffer objects."
  (cl-remove-if-not
   #'gemini-cli--buffer-p
   (buffer-list)))

(defun gemini-cli--find-gemini-buffers-for-directory (directory)
  "Find all active Gemini buffers for a specific DIRECTORY.

Returns a list of buffer objects."
  (cl-remove-if-not
   (lambda (buf)
     (let ((buf-dir (gemini-cli--extract-directory-from-buffer-name (buffer-name buf))))
       (and buf-dir
            (string= (file-truename (abbreviate-file-name directory))
                     (file-truename buf-dir)))))
   (gemini-cli--find-all-gemini-buffers)))

(defun gemini-cli--extract-directory-from-buffer-name (buffer-name)
  "Extract the directory path from a Gemini BUFFER-NAME.

For example, *gemini:/path/to/project/* returns /path/to/project/.
For example, *gemini:/path/to/project/:tests* returns /path/to/project/."
  (when (string-match "^\\*gemini:\\([^:]+\\)\\(?::\\([^*]+\\)\\)?\\*$" buffer-name)
    (match-string 1 buffer-name)))

(defun gemini-cli--extract-instance-name-from-buffer-name (buffer-name)
  "Extract the instance name from a Gemini BUFFER-NAME.

For example, *gemini:/path/to/project/:tests* returns \"tests\".
For example, *gemini:/path/to/project/* returns nil."
  (when (string-match "^\\*gemini:\\([^:]+\\)\\(?::\\([^*]+\\)\\)?\\*$" buffer-name)
    (match-string 2 buffer-name)))

(defun gemini-cli--buffer-display-name (buffer)
  "Create a display name for Gemini BUFFER.

Returns a formatted string like `project:instance (directory)' or
`project (directory)'."
  (let* ((name (buffer-name buffer))
         (dir (gemini-cli--extract-directory-from-buffer-name name))
         (instance-name (gemini-cli--extract-instance-name-from-buffer-name name)))
    (if instance-name
        (format "%s:%s (%s)"
                (file-name-nondirectory (directory-file-name dir))
                instance-name
                dir)
      (format "%s (%s)"
              (file-name-nondirectory (directory-file-name dir))
              dir))))

(defun gemini-cli--buffers-to-choices (buffers &optional simple-format)
  "Convert BUFFERS list to an alist of (display-name . buffer) pairs.

If SIMPLE-FORMAT is non-nil, use just the instance name as display name."
  (mapcar (lambda (buf)
            (let ((display-name (if simple-format
                                    (or (gemini-cli--extract-instance-name-from-buffer-name
                                         (buffer-name buf))
                                        "default")
                                  (gemini-cli--buffer-display-name buf))))
              (cons display-name buf)))
          buffers))

(defun gemini-cli--select-buffer-from-choices (prompt buffers &optional simple-format)
  "Prompt user to select a buffer from BUFFERS list using PROMPT.

If SIMPLE-FORMAT is non-nil, use simplified display names.
Returns the selected buffer or nil."
  (when buffers
    (let* ((choices (gemini-cli--buffers-to-choices buffers simple-format))
           (selection (completing-read prompt
                                       (mapcar #'car choices)
                                       nil t)))
      (cdr (assoc selection choices)))))

(defun gemini-cli--prompt-for-gemini-buffer ()
  "Prompt user to select from available Gemini buffers.

Returns the selected buffer or nil if canceled. If a buffer is selected,
it's remembered for the current directory."
  (let* ((current-dir (gemini-cli--directory))
         (gemini-buffers (gemini-cli--find-all-gemini-buffers)))
    (when gemini-buffers
      (let* ((prompt (substitute-command-keys
                      (format "No Gemini instance running in %s. Cancel (\\[keyboard-quit]), or select Gemini instance: "
                              (abbreviate-file-name current-dir))))
             (selected-buffer (gemini-cli--select-buffer-from-choices prompt gemini-buffers)))
        ;; Remember the selection for this directory
        (when selected-buffer
          (puthash current-dir selected-buffer gemini-cli--directory-buffer-map))
        selected-buffer))))

(defun gemini-cli--get-or-prompt-for-buffer ()
  "Get Gemini buffer for current directory or prompt for selection.

First checks for Gemini buffers in the current directory. If there are
multiple, prompts the user to select one. If there are none, checks if
there's a remembered selection for this directory. If not, and there are
other Gemini buffers running, prompts the user to select one. Returns
the buffer or nil."
  (let* ((current-dir (gemini-cli--directory))
         (dir-buffers (gemini-cli--find-gemini-buffers-for-directory current-dir)))
    (cond
     ;; Multiple buffers for this directory - prompt for selection
     ((> (length dir-buffers) 1)
      (gemini-cli--select-buffer-from-choices
       (format "Select Gemini instance for %s: "
               (abbreviate-file-name current-dir))
       dir-buffers
       t))  ; Use simple format (just instance names)
     ;; Single buffer for this directory - use it
     ((= (length dir-buffers) 1)
      (car dir-buffers))
     ;; No buffers for this directory - check remembered or prompt for other directories
     (t
      ;; Check for remembered selection for this directory
      (let ((remembered-buffer (gethash current-dir gemini-cli--directory-buffer-map)))
        (if (and remembered-buffer (buffer-live-p remembered-buffer))
            remembered-buffer
          ;; No valid remembered buffer, check for other Gemini instances
          (let ((other-buffers (gemini-cli--find-all-gemini-buffers)))
            (when other-buffers
              (gemini-cli--prompt-for-gemini-buffer)))))))))

(defun gemini-cli--switch-to-selected-buffer (selected-buffer)
  "Switch to SELECTED-BUFFER if it's not the current buffer.

This is used after command functions to ensure we switch to the
selected Gemini buffer when the user chose a different instance."
  (when (and selected-buffer
             (not (eq selected-buffer (current-buffer))))
    (pop-to-buffer selected-buffer)))

(defun gemini-cli--buffer-name (&optional instance-name)
  "Generate the Gemini buffer name based on project or current buffer file.

If INSTANCE-NAME is provided, include it in the buffer name.
If not in a project and no buffer file, raise an error."
  (let ((dir (gemini-cli--directory)))
    (if dir
        (if instance-name
            (format "*gemini:%s:%s*" (abbreviate-file-name (file-truename dir)) instance-name)
          (format "*gemini:%s*" (abbreviate-file-name (file-truename dir))))
      (error "Cannot determine Gemini directory - no `default-directory'!"))))

(defun gemini-cli--prompt-for-instance-name (dir existing-instance-names &optional force-prompt)
  "Prompt user for a new instance name for directory DIR.

EXISTING-INSTANCE-NAMES is a list of existing instance names.
If FORCE-PROMPT is non-nil, always prompt even if no instances exist."
  (if (or existing-instance-names force-prompt)
      (let ((proposed-name ""))
        (while (or (string-empty-p proposed-name)
                   (member proposed-name existing-instance-names))
          (setq proposed-name
                (read-string (if (and existing-instance-names (not force-prompt))
                                 (format "Instances already running for %s (existing: %s), new instance name: "
                                         (abbreviate-file-name dir)
                                         (mapconcat #'identity existing-instance-names ", "))
                               (format "Instance name for %s: " (abbreviate-file-name dir)))
                             nil nil proposed-name))
          (cond
           ((string-empty-p proposed-name)
            (message "Instance name cannot be empty. Please enter a name.")
            (sit-for 1))
           ((member proposed-name existing-instance-names)
            (message "Instance name '%s' already exists. Please choose a different name." proposed-name)
            (sit-for 1))))
        proposed-name)
    "default"))

(defun gemini-cli--show-not-running-message ()
  "Show a message that Gemini is not running in any directory."
  (message "Gemini is not running"))

(defun gemini-cli--kill-buffer (buffer)
  "Kill a Gemini BUFFER by cleaning up hooks and processes."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      ;; Remove the adjust window size advice if it was added
      (when gemini-cli-optimize-window-resize
        (advice-remove (gemini-cli--term-get-adjust-process-window-size-fn gemini-cli-terminal-backend) #'gemini-cli--adjust-window-size-advice))
      ;; Remove vterm advice if using vterm backend
      (when (eq gemini-cli-terminal-backend 'vterm)
        (advice-remove 'vterm--filter #'gemini-cli--vterm-bell-detector)
        (advice-remove 'vterm--filter #'gemini-cli--vterm-multiline-buffer-filter))
      ;; Clean the window widths hash table
      (when gemini-cli--window-widths
        (clrhash gemini-cli--window-widths))
      ;; Kill the process
      (gemini-cli--term-kill-process gemini-cli-terminal-backend buffer))))

(defun gemini-cli--cleanup-directory-mapping ()
  "Remove entries from directory-buffer map when this buffer is killed.

This function is added to `kill-buffer-hook' in Gemini buffers to clean up
the remembered directory->buffer associations."
  (let ((dying-buffer (current-buffer)))
    (maphash (lambda (dir buffer)
               (when (eq buffer dying-buffer)
                 (remhash dir gemini-cli--directory-buffer-map)))
             gemini-cli--directory-buffer-map)))

(defun gemini-cli--get-buffer-file-name ()
  "Get the file name associated with the current buffer."
  (when buffer-file-name
    (file-local-name (file-truename buffer-file-name))))

(defun gemini-cli--format-file-reference (&optional file-name line-start line-end)
  "Format a file reference in the @file:line style.

FILE-NAME is the file path.  If nil, get from current buffer.
LINE-START is the starting line number.  If nil, use current line.
LINE-END is the ending line number for a range.  If nil, format single line."
  (let ((file (or file-name (gemini-cli--get-buffer-file-name)))
        (start (or line-start (line-number-at-pos)))
        (end line-end))
    (when file
      (if end
          (format "@%s:%d-%d" file start end)
        (format "@%s:%d" file start)))))

(defun gemini-cli--do-send-command (cmd)
  "Send a command CMD to Gemini if Gemini buffer exists.

After sending the command, move point to the end of the buffer.
Returns the selected Gemini buffer or nil."
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (progn
        (with-current-buffer gemini-cli-buffer
          (gemini-cli--term-send-string gemini-cli-terminal-backend cmd)
          (sleep-for 0.1)
          (gemini-cli--term-send-string gemini-cli-terminal-backend (kbd "RET"))
          (display-buffer gemini-cli-buffer))
        gemini-cli-buffer)
    (gemini-cli--show-not-running-message)
    nil))

(defun gemini-cli--start (arg extra-switches &optional force-prompt force-switch-to-buffer)
  "Start Gemini with given command-line EXTRA-SWITCHES.

ARG is the prefix argument controlling directory and buffer switching.
EXTRA-SWITCHES is a list of additional command-line switches to pass to Gemini.
If FORCE-PROMPT is non-nil, always prompt for instance name.
If FORCE-SWITCH-TO-BUFFER is non-nil, always switch to the Gemini buffer.

With single prefix ARG (\\[universal-argument]), switch to buffer after creating.
With double prefix ARG (\\[universal-argument] \\[universal-argument]), prompt for the project directory."
  (let* ((dir (if (equal arg '(16))     ; Double prefix
                  (read-directory-name "Project directory: ")
                (gemini-cli--directory)))
         (switch-after (or (equal arg '(4)) force-switch-to-buffer)) ; Single prefix or force-switch-to-buffer
         (default-directory dir)
         ;; Check for existing Gemini instances in this directory
         (existing-buffers (gemini-cli--find-gemini-buffers-for-directory dir))
         ;; Get existing instance names
         (existing-instance-names (mapcar (lambda (buf)
                                            (or (gemini-cli--extract-instance-name-from-buffer-name
                                                 (buffer-name buf))
                                                "default"))
                                          existing-buffers))
         ;; Prompt for instance name (only if instances exist, or force-prompt is true)
         (instance-name (gemini-cli--prompt-for-instance-name dir existing-instance-names force-prompt))
         (buffer-name (gemini-cli--buffer-name instance-name))
         (program-switches (if extra-switches
                               (append gemini-cli-program-switches extra-switches)
                             gemini-cli-program-switches))

         ;; Set process-adaptive-read-buffering to nil to avoid flickering while Gemini is processing
         (process-adaptive-read-buffering nil)

         ;; Start the terminal process
         (buffer (gemini-cli--term-make gemini-cli-terminal-backend buffer-name gemini-cli-program program-switches)))

    ;; Check if the gemini program is available
    (unless (executable-find gemini-cli-program)
      (error "Gemini CLI program '%s' not found in PATH" gemini-cli-program))

    ;; Check if buffer was successfully created
    (unless (buffer-live-p buffer)
      (error "Failed to create Gemini CLI buffer"))

    ;; setup gemini buffer
    (with-current-buffer buffer

      ;; Configure terminal with backend-specific settings
      (gemini-cli--term-configure gemini-cli-terminal-backend)

      ;; Initialize the window widths hash table
      (setq gemini-cli--window-widths (make-hash-table :test 'eq :weakness 'key))

      ;; Set up window width tracking if optimization is enabled
      (when gemini-cli-optimize-window-resize
        (advice-add (gemini-cli--term-get-adjust-process-window-size-fn gemini-cli-terminal-backend) :around #'gemini-cli--adjust-window-size-advice))

      ;; Setup our custom key bindings
      (gemini-cli--term-setup-keymap gemini-cli-terminal-backend)

      ;; Customize terminal faces
      (gemini-cli--term-customize-faces gemini-cli-terminal-backend)

      ;; remove underlines from _>_
      (face-remap-add-relative 'nobreak-space :underline nil)

      ;; set buffer face
      (buffer-face-set :inherit 'gemini-cli-repl-face)

      ;; disable scroll bar, fringes
      (setq-local vertical-scroll-bar nil)
      (setq-local fringe-mode 0)

      ;; Add cleanup hook to remove directory mappings when buffer is killed
      (add-hook 'kill-buffer-hook #'gemini-cli--cleanup-directory-mapping nil t)

      ;; run start hooks
      (run-hooks 'gemini-cli-start-hook)

      ;; Disable vertical scroll bar in gemini buffer
      (setq-local vertical-scroll-bar nil)

      ;; Display buffer, setting window parameters
      (let ((window (display-buffer-in-side-window buffer '((side . right)(window-width . 0.4)))))
        (when window
          ;; turn off fringes and margins in the Gemini buffer
          (set-window-parameter window 'left-margin-width 0)
          (set-window-parameter window 'right-margin-width 0)
          (set-window-parameter window 'left-fringe-width 0)
          (set-window-parameter window 'right-fringe-width 0)
          ;; set no-delete-other-windows parameter for gemini-cli window
          (set-window-parameter window 'no-delete-other-windows gemini-cli-no-delete-other-windows))))

    ;; switch to the Gemini buffer if asked to
    (when switch-after
      (pop-to-buffer buffer))))

;;;###autoload
(defun gemini-cli (&optional arg)
  "Start Gemini in an eat terminal and enable `gemini-cli-mode'.

If current buffer belongs to a project start Gemini in the project's
root directory. Otherwise start in the directory of the current buffer
file, or the current value of `default-directory' if no project and no
buffer file.

With single prefix ARG (\\[universal-argument]), switch to buffer after creating.
With double prefix ARG (\\[universal-argument] \\[universal-argument]), prompt for the project directory."
  (interactive "P")
  (gemini-cli--start arg nil))

;;;###autoload
(defun gemini-cli-start-in-directory (&optional arg)
  "Prompt for a directory and start Gemini there.

This is a convenience command equivalent to using `gemini-cli` with
double prefix arg (\\[universal-argument] \\[universal-argument]).

With prefix ARG (\\[universal-argument]), switch to buffer after creating."
  (interactive "P")
  ;; Always prompt for directory (like double prefix)
  ;; If user gave us a prefix arg, also switch to buffer after creating
  (let ((dir (read-directory-name "Project directory: ")))
    ;; We need to temporarily override gemini-cli--directory to return our chosen dir
    (cl-letf (((symbol-function 'gemini-cli--directory) (lambda () dir)))
      (gemini-cli (when arg '(4))))))

;;;###autoload
(defun gemini-cli-continue (&optional arg)
  "Start Gemini and continue the previous conversation.

This command starts Gemini with the --continue flag to resume
where you left off in your last session.

If current buffer belongs to a project start Gemini in the project's
root directory. Otherwise start in the directory of the current buffer
file, or the current value of `default-directory' if no project and no
buffer file.

With prefix ARG (\\[universal-argument]), switch to buffer after creating.
With double prefix ARG (\\[universal-argument] \\[universal-argument]), prompt for the project directory."
  (interactive "P")
  (gemini-cli--start arg '("--continue")))

;;;###autoload
(defun gemini-cli-resume (arg)
  "Resume a specific Gemini session.

This command starts Gemini with the --resume flag to resume a specific
past session. Gemini will present an interactive list of past sessions
to choose from.

If current buffer belongs to a project start Gemini in the project's
root directory. Otherwise start in the directory of the current buffer
file, or the current value of `default-directory' if no project and no
 buffer file.

With double prefix ARG (\\[universal-argument] \\[universal-argument]), prompt for the project directory."
  (interactive "P")

  (let ((extra-switches '("--resume")))
    (gemini-cli--start arg extra-switches nil t))
  (gemini-cli--term-send-string gemini-cli-terminal-backend "")
  (goto-char (point-min)))

;;;###autoload
(defun gemini-cli-new-instance (&optional arg)
  "Create a new Gemini instance, prompting for instance name.

This command always prompts for an instance name, unlike `gemini-cli'
which uses \"default\" when no instances exist.

If current buffer belongs to a project start Gemini in the project's
root directory. Otherwise start in the directory of the current buffer
file, or the current value of `default-directory' if no project and no
buffer file.

With single prefix ARG (\\[universal-argument]), switch to buffer after creating.
With double prefix ARG (\\[universal-argument] \\[universal-argument]), prompt
for the project directory."
  (interactive "P")

  ;; Call gemini-cli--start with force-prompt=t
  (gemini-cli--start arg nil t))

(defun gemini-cli--format-errors-at-point ()
  "Format errors at point as a string with file and line numbers.
First tries flycheck errors if flycheck is enabled, then falls back
to help-at-pt (used by flymake and other systems).
Returns a string with the errors or a message if no errors found."
  (interactive)
  (cond
   ;; Try flycheck first if available and enabled
   ((and (featurep 'flycheck) (bound-and-true-p flycheck-mode))
    (let ((errors (flycheck-overlay-errors-at (point)))
          (result ""))
      (if (not errors)
          "No flycheck errors at point"
        (dolist (err errors)
          (let ((file (flycheck-error-filename err))
                (line (flycheck-error-line err))
                (msg (flycheck-error-message err)))
            (setq result (concat result
                                 (format "%s:%d: %s\n"
                                         file
                                         line
                                         msg)))))
        (string-trim-right result))))
   ;; Fall back to help-at-pt-kbd-string (works with flymake and other sources)
   ((help-at-pt-kbd-string)
    (let ((help-str (help-at-pt-kbd-string)))
      (if (not (null help-str))
          (substring-no-properties help-str)
        "No help string available at point")))
   ;; No errors found by any method
   (t "No errors at point")))

(defun gemini-cli--pulse-modeline ()
  "Pulse the modeline to provide visual notification."
  ;; First pulse - invert
  (invert-face 'mode-line)
  (run-at-time 0.1 nil
               (lambda ()
                 ;; Return to normal
                 (invert-face 'mode-line)
                 ;; Second pulse
                 (run-at-time 0.1 nil
                              (lambda ()
                                (invert-face 'mode-line)
                                ;; Final return to normal
                                (run-at-time 0.1 nil
                                             (lambda ()
                                               (invert-face 'mode-line))))))))

(defun gemini-cli-default-notification (title message)
  "Default notification function that displays a message and pulses the modeline.

TITLE is the notification title.
MESSAGE is the notification body."
  ;; Display the message
  (message "%s: %s" title message)
  ;; Pulse the modeline for visual feedback
  (gemini-cli--pulse-modeline)
  (message "%s: %s" title message))

(defun gemini-cli--notify (_terminal)
  "Notify the user that Gemini has finished and is awaiting input.

TERMINAL is the eat terminal parameter (not used)."
  (when gemini-cli-enable-notifications
    (funcall gemini-cli-notification-function
             "Gemini Ready"
             "Waiting for your response")))

(defun gemini-cli--vterm-bell-detector (orig-fun process input)
  "Detect bell characters in vterm output and trigger notifications.

ORIG-FUN is the original vterm--filter function.
PROCESS is the vterm process.
INPUT is the terminal output string."
  (when (and (string-match-p "\007" input)
             (buffer-local-value 'gemini-cli-mode (process-buffer process))
             ;; Ignore bells in OSC sequences (terminal title updates)
             (not (string-match-p "]0;.*\007" input)))
    (gemini-cli--notify nil))

  (funcall orig-fun process input))

(defvar-local gemini-cli--vterm-multiline-buffer nil
  "Buffer for accumulating multi-line vterm output.")

(defvar-local gemini-cli--vterm-multiline-buffer-timer nil
  "Timer for processing buffered multi-line vterm output.")

(defun gemini-cli--vterm-multiline-buffer-filter (orig-fun process input)
  "Buffer vterm output when it appears to be redrawing multi-line input.
This prevents flickering when Gemini redraws its input box as it expands
to multiple lines. We detect this by looking for escape sequences that
indicate cursor positioning and line clearing operations.

ORIG-FUN is the original vterm--filter function.
PROCESS is the vterm process.
INPUT is the terminal output string."
  (if (not gemini-cli-vterm-buffer-multiline-output)
      ;; Feature disabled, pass through normally
      (funcall orig-fun process input)
    (with-current-buffer (process-buffer process)
      ;; Check if this looks like multi-line input box redraw
      ;; Common patterns when redrawing multi-line input:
      ;; - ESC[K (clear to end of line)
      ;; - ESC[<n>;<m>H (cursor positioning)
      ;; - ESC[<n>A/B/C/D (cursor movement)
      ;; - Multiple of these in sequence
      (let ((has-clear-line (string-match-p "\033\\[K" input))
            (has-cursor-pos (string-match-p "\033\\[[0-9]+;[0-9]+H" input))
            (has-cursor-move (string-match-p "\033\\[[0-9]*[ABCD]" input))
            (escape-count (cl-count ?\033 input)))

        ;; If we see multiple escape sequences that look like redrawing,
        ;; or we're already buffering, add to buffer
        (if (or (and (>= escape-count 3)
                     (or has-clear-line has-cursor-pos has-cursor-move))
                gemini-cli--vterm-multiline-buffer)
            (progn
              ;; Add to buffer
              (setq gemini-cli--vterm-multiline-buffer
                    (concat gemini-cli--vterm-multiline-buffer input))
              ;; Cancel existing timer
              (when gemini-cli--vterm-multiline-buffer-timer
                (cancel-timer gemini-cli--vterm-multiline-buffer-timer))
              ;; Set timer with configurable delay
              ;; This is enough to collect a burst of updates but not noticeable to user
              (setq gemini-cli--vterm-multiline-buffer-timer
                    (run-at-time gemini-cli-vterm-multiline-delay nil
                                 (lambda (buf)
                                   (when (buffer-live-p buf)
                                     (with-current-buffer buf
                                       (when gemini-cli--vterm-multiline-buffer
                                         (let ((inhibit-redisplay t)
                                               (data gemini-cli--vterm-multiline-buffer))
                                           ;; Clear buffer first to prevent recursion
                                           (setq gemini-cli--vterm-multiline-buffer nil
                                                 gemini-cli--vterm-multiline-buffer-timer nil)
                                           ;; Process all buffered data at once
                                           (funcall orig-fun
                                                    (get-buffer-process buf)
                                                    data))))))
                                 (current-buffer))))
          ;; Not multi-line redraw, process normally
          (funcall orig-fun process input))))))

(defun gemini-cli--adjust-window-size-advice (orig-fun &rest args)
  "Advice to only signal on width change.

Works with `eat--adjust-process-window-size' or
`vterm--adjust-process-window-size' to prevent unnecessary reflows.

Returns the size returned by ORIG-FUN only when the width of any Gemini
window has changed, not when only the height has changed. This prevents
unnecessary terminal reflows when only vertical space changes.

ARGS is passed to ORIG-FUN unchanged."
  (let ((result (apply orig-fun args)))
    ;; Check all windows for Gemini buffers
    (let ((width-changed nil))
      (dolist (window (window-list))
        (let ((buffer (window-buffer window)))
          (when (and buffer (gemini-cli--buffer-p buffer))
            (let ((current-width (window-width window))
                  (stored-width (gethash window gemini-cli--window-widths)))
              ;; Check if this is a new window or if width changed
              (when (or (not stored-width) (/= current-width stored-width))
                (setq width-changed t)
                ;; Update stored width
                (puthash window current-width gemini-cli--window-widths))))))
      ;; Return result only if a Gemini window width changed and
      ;; we're not in read-only mode. otherwise nil. Nil means do
      ;; not send a window size changed event to the Gemini process.
      (if (and width-changed (not (gemini-cli--term-in-read-only-p gemini-cli-terminal-backend)))
          result
        nil))))

;;;; Interactive Commands

;;;###autoload
(defun gemini-cli-send-region (&optional arg)
  "Send the current region to Gemini.

If no region is active, send the entire buffer if it's not too large.
For large buffers, ask for confirmation first.

With prefix ARG, prompt for instructions to add to the text before
sending. With two prefix ARGs (C-u C-u), both add instructions and
switch to Gemini buffer."
  (interactive "P")
  (let* ((text (if (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (if (> (buffer-size) gemini-cli-large-buffer-threshold)
                     (when (yes-or-no-p "Buffer is large.  Send anyway? ")
                       (buffer-substring-no-properties (point-min) (point-max)))
                   (buffer-substring-no-properties (point-min) (point-max)))))
         (prompt (cond
                  ((equal arg '(4))     ; C-u
                   (read-string "Instructions for Gemini: "))
                  ((equal arg '(16))    ; C-u C-u
                   (read-string "Instructions for Gemini: "))
                  (t nil)))
         (full-text (if prompt
                        (format "%s\n\n%s" prompt text)
                      text)))
    (when full-text
      (let ((selected-buffer (gemini-cli--do-send-command full-text)))
        (when (and (equal arg '(16)) selected-buffer) ; Only switch buffer with C-u C-u
          (pop-to-buffer selected-buffer))))))

;;;###autoload
(defun gemini-cli-toggle ()
  "Show or hide the Gemini window.

If the Gemini buffer doesn't exist, create it."
  (interactive)
  (let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
    (if gemini-cli-buffer
        (if (get-buffer-window gemini-cli-buffer)
            (delete-window (get-buffer-window gemini-cli-buffer))
      (let ((window (display-buffer-in-side-window gemini-cli-buffer '((side . right)(window-width . 0.4)))))
            ;; set no-delete-other-windows parameter for gemini-cli window
            (set-window-parameter window 'no-delete-other-windows gemini-cli-no-delete-other-windows)))
      (gemini-cli--show-not-running-message))))

;;;###autoload
(defun gemini-cli--switch-to-all-instances-helper ()
  "Helper function to switch to a Gemini buffer from all available instances.

Returns t if a buffer was selected and switched to, nil otherwise."
  (let ((all-buffers (gemini-cli--find-all-gemini-buffers)))
    (cond
     ((null all-buffers)
      (gemini-cli--show-not-running-message)
      nil)
     ((= (length all-buffers) 1)
      ;; Only one buffer, just switch to it
      (pop-to-buffer (car all-buffers))
      t)
     (t
      ;; Multiple buffers, let user choose
      (let ((selected-buffer (gemini-cli--select-buffer-from-choices
                              "Select Gemini instance: "
                              all-buffers)))
        (when selected-buffer
          (pop-to-buffer selected-buffer)
          t))))))

(defun gemini-cli-switch-to-buffer (&optional arg)
  "Switch to the Gemini buffer if it exists.

With prefix ARG, show all Gemini instances across all directories."
  (interactive "P")
  (if arg
      ;; With prefix arg, show all Gemini instances
      (gemini-cli--switch-to-all-instances-helper)
    ;; Without prefix arg, use normal behavior
    (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
        (pop-to-buffer gemini-cli-buffer)
      (gemini-cli--show-not-running-message))))

;;;###autoload
(defun gemini-cli-select-buffer ()
  "Select and switch to a Gemini buffer from all running instances.

This command shows all Gemini instances across all projects and
directories, allowing you to choose which one to switch to."
  (interactive)
  (gemini-cli--switch-to-all-instances-helper))

(defun gemini-cli--kill-all-instances ()
  "Kill all Gemini instances across all directories."
  (let ((all-buffers (gemini-cli--find-all-gemini-buffers)))
    (if all-buffers
        (let* ((buffer-count (length all-buffers))
               (plural-suffix (if (= buffer-count 1) "" "s")))
          (if gemini-cli-confirm-kill
              (when (yes-or-no-p (format "Kill %d Gemini instance%s? " buffer-count plural-suffix))
                (dolist (buffer all-buffers)
                  (gemini-cli--kill-buffer buffer))
                (message "%d Gemini instance%s killed" buffer-count plural-suffix))
            (dolist (buffer all-buffers)
              (gemini-cli--kill-buffer buffer))
            (message "%d Gemini instance%s killed" buffer-count plural-suffix)))
      (gemini-cli--show-not-running-message))))

;;;###autoload
(defun gemini-cli-kill ()
  "Kill Gemini process and close its window."
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (if gemini-cli-confirm-kill
          (when (yes-or-no-p "Kill Gemini instance? ")
            (gemini-cli--kill-buffer gemini-cli-buffer)
            (message "Gemini instance killed"))
        (gemini-cli--kill-buffer gemini-cli-buffer)
        (message "Gemini instance killed"))
    (gemini-cli--show-not-running-message)))

;;;###autoload
(defun gemini-cli-kill-all ()
  "Kill ALL Gemini processes across all directories."
  (interactive)
  (gemini-cli--kill-all-instances))

;;;###autoload
(defun gemini-cli-send-command (&optional arg)
  "Read a Gemini command from the minibuffer and send it.

With prefix ARG, switch to the Gemini buffer after sending CMD."
  (interactive)
  (setq cmd (completing-read "Gemini Command: " '() nil nil nil nil ""))
  (let ((selected-buffer (gemini-cli--do-send-command cmd)))
    (when (and arg selected-buffer)
      (pop-to-buffer selected-buffer))))

;;;###autoload
(defun gemini-cli-send-shell (cmd &optional arg)
  "Read a Gemini command from the minibuffer and send it.

With prefix ARG, switch to the Gemini buffer after sending CMD."
  (interactive "sGemini command: !\nP")
  (let ((selected-buffer (gemini-cli--do-send-command (concat "!" cmd))))
    (when selected-buffer
      (with-current-buffer selected-buffer
        (gemini-cli--do-send-command "!")))
    (when (and arg selected-buffer)
      (pop-to-buffer selected-buffer))))

;;;###autoload
(defun gemini-cli-send-command-with-context (cmd &optional arg)
  "Read a Gemini command and send it with current file and line context.

If region is active, include region line numbers.
With prefix ARG, switch to the Gemini buffer after sending CMD."
  (interactive "sGemini command: \nP")
  (let* ((file-ref (if (use-region-p)
                       (gemini-cli--format-file-reference
                        nil
                        (line-number-at-pos (region-beginning))
                        (line-number-at-pos (region-end)))
                     (gemini-cli--format-file-reference)))
         (cmd-with-context (if file-ref
                               (format "%s\n%s" cmd file-ref)
                             cmd)))
    (let ((selected-buffer (gemini-cli--do-send-command cmd-with-context)))
      (when (and arg selected-buffer)
        (pop-to-buffer selected-buffer)))))

;;;###autoload
(defun gemini-cli-send-return ()
  "Send <return> to the Gemini CLI REPL.

This is useful for saying Yes when Gemini asks for confirmation without
having to switch to the REPL buffer."
  (interactive)
  (gemini-cli--do-send-command ""))

;;;###autoload
(defun gemini-cli-send-1 ()
  "Send \"1\" to the Gemini CLI REPL.

This selects the first option when Gemini presents a numbered menu."
  (interactive)
  (gemini-cli--do-send-command "1"))

;;;###autoload
(defun gemini-cli-send-2 ()
  "Send \"2\" to the Gemini CLI REPL.

This selects the second option when Gemini presents a numbered menu."
  (interactive)
  (gemini-cli--do-send-command "2"))

;;;###autoload
(defun gemini-cli-send-3 ()
  "Send \"3\" to the Gemini CLI REPL.

This selects the third option when Gemini presents a numbered menu."
  (interactive)
  (gemini-cli--do-send-command "3"))

;;;###autoload
(defun gemini-cli-send-escape ()
  "Send <escape> to the Gemini CLI REPL.

This is useful for saying \"No\" when Gemini asks for confirmation without
having to switch to the REPL buffer."
  (interactive)
  (gemini-cli--with-buffer
   (gemini-cli--term-send-string gemini-cli-terminal-backend (kbd "ESC"))))

;;;###autoload
(defun gemini-cli-send-file (file-path)
  "Send the specified FILE-PATH to Gemini prefixed with `@'.

FILE-PATH should be an absolute path to the file to send."
  (interactive "fFile to send to Gemini: ")
  (let ((command (format "@%s" (expand-file-name file-path))))
    (gemini-cli--do-send-command command)))

;;;###autoload
(defun gemini-cli-send-buffer-file (&optional arg)
  "Send the file associated with current buffer to Gemini prefixed with `@'.

With prefix ARG, prompt for instructions to add to the file before sending.
With two prefix ARGs, both add instructions and switch to Gemini buffer."
  (interactive "P")
  (let ((file-path (gemini-cli--get-buffer-file-name)))
    (if file-path
        (let* ((prompt (when arg
                        (read-string "Instructions for Gemini: ")))
               (command (if prompt
                           (format "%s\n\n@%s" prompt file-path)
                         (format "@%s" file-path))))
          (let ((selected-buffer (gemini-cli--do-send-command command)))
            (when (and (equal arg '(16)) selected-buffer) ; Only switch buffer with C-u C-u
              (pop-to-buffer selected-buffer))))
      (error "Current buffer is not associated with a file"))))

(defun gemini-cli--send-meta-return ()
  "Send Meta-Return key sequence to the terminal."
  (interactive)
  (gemini-cli--term-send-string gemini-cli-terminal-backend "\e\C-m"))

(defun gemini-cli--send-return ()
  "Send Return key to the terminal."
  (interactive)
  (gemini-cli--term-send-string gemini-cli-terminal-backend (kbd "RET")))

;;;###autoload
(defun gemini-cli-cycle-mode ()
  "Send Shift-Tab to Gemini to cycle between modes.

Gemini uses Shift-Tab to cycle through:
- Default mode
- Auto-accept edits mode
- Plan mode"
  (interactive)
  (gemini-cli--with-buffer
   (gemini-cli--term-send-string gemini-cli-terminal-backend "\e[Z")))

;; (define-key key-translation-map (kbd "ESC") "")

;;;###autoload
(defun gemini-cli-fork ()
  "Jump to a previous conversation by invoking the Gemini fork command.

Sends <escape><escape> to the Gemini CLI REPL."
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (gemini-cli--term-send-string gemini-cli-terminal-backend "")
        ;; (display-buffer gemini-cli-buffer)
        (pop-to-buffer gemini-cli-buffer))
    (gemini-cli--show-not-running-message)))

;;;###autoload
(defun gemini-cli-fix-error-at-point (&optional arg)
  "Ask Gemini to fix the error at point.

Gets the error message, file name, and line number, and instructs Gemini
to fix the error. Supports both flycheck and flymake error systems, as well
as any system that implements help-at-pt.

With prefix ARG, switch to the Gemini buffer after sending."
  (interactive "P")
  (let* ((error-text (gemini-cli--format-errors-at-point))
         (file-ref (gemini-cli--format-file-reference)))
    (if (string= error-text "No errors at point")
        (message "No errors found at point")
      (let ((command (format "Fix this error at %s:\nDo not run any external linter or other program, just fix the error at point using the context provided in the error message: <%s>"
                             (or file-ref "current position") error-text)))
        (let ((selected-buffer (gemini-cli--do-send-command command)))
          (when (and arg selected-buffer)
            (pop-to-buffer selected-buffer)))))))

;;;###autoload
(defun gemini-cli-read-only-mode ()
  "Enter read-only mode in Gemini buffer with visible cursor.

In this mode, you can interact with the terminal buffer just like a
regular buffer. This mode is useful for selecting text in the Gemini
buffer. However, you are not allowed to change the buffer contents or
enter Gemini commands.

Use `gemini-cli-exit-read-only-mode' to switch back to normal mode."
  (interactive)
  (gemini-cli--with-buffer
   (gemini-cli--term-read-only-mode gemini-cli-terminal-backend)
   (message "Gemini read-only mode enabled")))

;;;###autoload
(defun gemini-cli-exit-read-only-mode ()
  "Exit read-only mode and return to normal mode (eat semi-char mode)."
  (interactive)
  (gemini-cli--with-buffer
   (gemini-cli--term-interactive-mode gemini-cli-terminal-backend)
   (message "Gemini read-only disabled")))

;;;###autoload
(defun gemini-cli-toggle-read-only-mode ()
  "Toggle between read-only mode and normal mode.

In read-only mode you can interact with the terminal buffer just like a
regular buffer. This mode is useful for selecting text in the Gemini
buffer. However, you are not allowed to change the buffer contents or
enter Gemini commands."
  (interactive)
  (gemini-cli--with-buffer
   (if (not (gemini-cli--term-in-read-only-p gemini-cli-terminal-backend))
       (gemini-cli-read-only-mode)
     (gemini-cli-exit-read-only-mode))))

;;;; Mode definition
;;;###autoload
(define-minor-mode gemini-cli-mode
  "Minor mode for interacting with Gemini AI CLI.

When enabled, provides functionality for starting, sending commands to,
and managing Gemini sessions."
  :init-value nil
  :lighter " Gemini"
  :global t
  :group 'gemini-cli)

;;;; Provide the feature
(provide 'gemini-cli)

;;; gemini-cli.el ends here
