;;; gemini-cli.el --- Gemini CLI Emacs integration -*- lexical-binding: t; -*-

;; Author: Stephen Molitor <stevemolitor@gmail.com>
;; Version: 0.2.0
;; Package-Requires: ((emacs "30.0") (transient "0.7.5") (eat "0.9.2"))
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

;; Declare external variables and functions from eat package
(defvar eat--semi-char-mode)
(defvar eat-terminal)
(defvar eat--synchronize-scroll-function)
(declare-function eat-term-reset "eat" (terminal))
(declare-function eat-term-redisplay "eat" (terminal))
(declare-function eat--set-cursor "eat" (terminal &rest args))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat-term-display-beginning "eat" (terminal))
(declare-function eat-term-live-p "eat" (terminal))

;;;; Customization options
(defgroup gemini-cli nil
  "Gemini AI interface for Emacs."
  :group 'tools)

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

(defcustom gemini-cli-read-only-mode-cursor-type '(box nil nil)
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
  :group 'gemini-cli)

(defcustom gemini-cli-never-truncate-gemini-buffer nil
  "When non-nil, disable truncation of Gemini output buffer.

By default, Eat will truncate the terminal scrollback buffer when it
reaches a certain size.  This can cause Gemini's output to be cut off
when dealing with large responses.  Setting this to non-nil disables
the scrollback size limit, allowing Gemini to output unlimited content
without truncation.

Note: Disabling truncation may consume more memory for very large
outputs."
  :type 'boolean
  :group 'gemini-cli)

;; Forward declare variables to avoid compilation warnings
(defvar eat-terminal)
(defvar eat-term-name)
(defvar eat-invisible-cursor-type)
(declare-function eat-term-send-string "eat")
(declare-function eat-kill-process "eat")
(declare-function eat-make "eat")
(declare-function eat-emacs-mode "eat")
(declare-function eat-semi-char-mode "eat")

;; Forward declare flycheck functions
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

;;;; Key bindings
;;;###autoload (autoload 'gemini-cli-command-map "gemini-cli")
(defvar gemini-cli-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "/" 'gemini-cli-slash-commands)
    (define-key map "b" 'gemini-cli-switch-to-buffer)
    (define-key map "c" 'gemini-cli)
    (define-key map "e" 'gemini-cli-fix-error-at-point)
    (define-key map "k" 'gemini-cli-kill)
    (define-key map "m" 'gemini-cli-transient)
    (define-key map "n" 'gemini-cli-send-escape)
    (define-key map "f" 'gemini-cli-fork)
    (define-key map "r" 'gemini-cli-send-region)
    (define-key map "s" 'gemini-cli-send-command)
    (define-key map "t" 'gemini-cli-toggle)
    (define-key map "x" 'gemini-cli-send-command-with-context)
    (define-key map "y" 'gemini-cli-send-return)
    (define-key map "z" 'gemini-cli-toggle-read-only-mode)
    (define-key map "1" 'gemini-cli-send-1)
    (define-key map "2" 'gemini-cli-send-2)
    (define-key map "3" 'gemini-cli-send-3)
    (define-key map [tab] 'gemini-cli-cycle-mode)
    map)
  "Keymap for Gemini commands.")

;;;; Transient Menus
;;;###autoload (autoload 'gemini-cli-transient "gemini-cli" nil t)
(transient-define-prefix gemini-cli-transient ()
  "Gemini command menu."
  ["Gemini Commands"
   ["Manage Gemini" ("c" "Start Gemini" gemini-cli)
    ("t" "Toggle gemini window" gemini-cli-toggle)
    ("b" "Switch to Gemini buffer" gemini-cli-switch-to-buffer)
    ("k" "Kill Gemini" gemini-cli-kill)
    ("z" "Toggle read-only mode" gemini-cli-toggle-read-only-mode)]
   ["Send Commands to Gemini" ("s" "Send command" gemini-cli-send-command)
    ("x" "Send command with context" gemini-cli-send-command-with-context)
    ("r" "Send region or buffer" gemini-cli-send-region)
    ("e" "Fix error at point" gemini-cli-fix-error-at-point)
    ("f" "Fork (jump to previous conversation" gemini-cli-fork)
    ("/" "Slash Commands" gemini-cli-slash-commands)]
   ["Quick Responses" ("y" "Send <return> (\"Yes\")" gemini-cli-send-return)
    ("n" "Send <escape> (\"No\")" gemini-cli-send-escape)
    ("1" "Send \"1\"" gemini-cli-send-1)
    ("2" "Send \"2\"" gemini-cli-send-2)
    ("3" "Send \"3\"" gemini-cli-send-3)
    ("TAB" "Cycle Gemini mode" gemini-cli-cycle-mode)]])


;;;###autoload (autoload 'gemini-cli-slash-commands "gemini-cli" nil t)
(transient-define-prefix gemini-cli-slash-commands ()
  "Gemini slash commands menu."
  ["Slash Commands"
   ["Basic Commands"
    ("c" "Clear" (lambda () (interactive) (gemini-cli--do-send-command "/clear")))
    ("o" "Compact" (lambda () (interactive) (gemini-cli--do-send-command "/compact")))
    ("f" "Config" (lambda () (interactive) (gemini-cli--do-send-command "/config")))
    ("t" "Cost" (lambda () (interactive) (gemini-cli--do-send-command "/cost")))
    ("d" "Doctor" (lambda () (interactive) (gemini-cli--do-send-command "/doctor")))
    ("x" "Exit" (lambda () (interactive) (gemini-cli--do-send-command "/exit")))
    ("h" "Help" (lambda () (interactive) (gemini-cli--do-send-command "/help")))]

   ["Special Commands"
    ("i" "Init" (lambda () (interactive) (gemini-cli--do-send-command "/init")))
    ("p" "PR" (lambda () (interactive) (gemini-cli--do-send-command "/pr")))
    ("r" "Release" (lambda () (interactive) (gemini-cli--do-send-command "/release")))
    ("b" "Bug" (lambda () (interactive) (gemini-cli--do-send-command "/bug")))
    ("v" "Review" (lambda () (interactive) (gemini-cli--do-send-command "/review")))]

   ["Additional Commands"
    ("e" "Terminal" (lambda () (interactive) (gemini-cli--do-send-command "/terminal")))
    ("m" "Theme" (lambda () (interactive) (gemini-cli--do-send-command "/theme")))
    ("v" "Vim" (lambda () (interactive) (gemini-cli--do-send-command "/vim")))
    ("a" "Approved" (lambda () (interactive) (gemini-cli--do-send-command "/approved")))
    ("l" "Logout" (lambda () (interactive) (gemini-cli--do-send-command "/logout")))
    ("g" "Login" (lambda () (interactive) (gemini-cli--do-send-command "/login")))]
   ])

;;;; Private util functions
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
   (lambda (buf)
     (string-match-p "^\\*gemini:" (buffer-name buf)))
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
    (switch-to-buffer selected-buffer)))

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

(defun gemini-cli--show-not-running-message ()
  "Show a message that Gemini is not running in any directory."
  (message "Gemini is not running"))

(defun gemini-cli--kill-buffer (buffer)
  "Kill a Gemini BUFFER by cleaning up hooks and processes.

This function handles the proper cleanup sequence for a Gemini buffer:
1. Remove the window configuration change hook
2. Kill the eat process
3. Kill the buffer"
  (with-current-buffer buffer
    (remove-hook 'window-configuration-change-hook #'gemini-cli--on-window-configuration-change t)
    (eat-kill-process)
    (kill-buffer buffer)))

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
    (file-truename buffer-file-name)))

(defun gemini-cli--do-send-command (cmd)
  "Send a command CMD to Gemini if Gemini buffer exists.

After sending the command, move point to the end of the buffer.
Returns the selected Gemini buffer or nil."
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (progn
        (with-current-buffer gemini-cli-buffer
          (eat-term-send-string eat-terminal cmd)
          (eat-term-send-string eat-terminal (kbd "RET"))
          (display-buffer gemini-cli-buffer))
        gemini-cli-buffer)
    (gemini-cli--show-not-running-message)
    nil))

(defun gemini-cli--setup-repl-faces ()
  "Setup faces for the Gemini REPL buffer.

Applies the `gemini-cli-repl-face' to all terminal-related faces
for consistent appearance."
  (dolist (face '(eat-shell-prompt-annotation-running
                  eat-shell-prompt-annotation-success
                  eat-shell-prompt-annotation-failure
                  eat-term-bold
                  eat-term-faint
                  eat-term-italic
                  eat-term-slow-blink
                  eat-term-fast-blink))
    (funcall 'face-remap-add-relative face :inherit 'gemini-cli-repl-face))
  (dotimes (i 10)
    (let ((face (intern (format "eat-term-font-%d" i))))
      (funcall 'face-remap-add-relative face :inherit 'gemini-cli-repl-face)))
  (dotimes (i 10)
    (let ((face (intern (format "eat-term-font-%d" i))))
      (funcall 'face-remap-add-relative face :inherit 'gemini-cli-repl-face)))
  (buffer-face-set :inherit 'gemini-cli-repl-face)
  (face-remap-add-relative 'nobreak-space :underline nil)
  (face-remap-add-relative 'eat-term-faint :foreground "#999999" :weight 'light))

(defun gemini-cli--synchronize-scroll (windows)
  "Synchronize scrolling and point between terminal and WINDOWS.

WINDOWS is a list of windows.  WINDOWS may also contain the special
symbol `buffer', in which case the point of current buffer is set.

This custom version keeps the prompt at the bottom of the window when
possible, preventing the scrolling up issue when editing other buffers."
  (dolist (window windows)
    (if (eq window 'buffer)
        (goto-char (eat-term-display-cursor eat-terminal))
      ;; Instead of always setting window-start to the beginning,
      ;; keep the prompt at the bottom of the window when possible.
      ;; Don't move the cursor around though when in eat-emacs-mode
      (when (not buffer-read-only)
        (let ((cursor-pos (eat-term-display-cursor eat-terminal))
              (term-beginning (eat-term-display-beginning eat-terminal)))
          ;; Set point first
          (set-window-point window cursor-pos)
          ;; Check if we should keep the prompt at the bottom
          (when (and (>= cursor-pos (- (point-max) 2))
                     (not (pos-visible-in-window-p cursor-pos window)))
            ;; Recenter with point at bottom of window
            (with-selected-window window
              (save-excursion
                (goto-char cursor-pos)
                (recenter -1))))
          ;; Otherwise, only adjust window-start if cursor is not visible
          (unless (pos-visible-in-window-p cursor-pos window)
            (set-window-start window term-beginning)))))))

(defun gemini-cli--on-window-configuration-change ()
  "Handle window configuration change for Gemini buffers.

Ensure all Gemini buffers stay scrolled to the bottom when window
configuration changes (e.g., when minibuffer opens/closes)."
  (dolist (gemini-buffer (gemini-cli--find-all-gemini-buffers))
    (with-current-buffer gemini-buffer
      ;; Get all windows showing this Gemini buffer
      (when-let ((windows (get-buffer-window-list gemini-buffer nil t)))
        (gemini-cli--synchronize-scroll windows)))))

(defvar gemini-cli--window-widths (make-hash-table :test 'eq :weakness 'key)
  "Hash table mapping windows to their last known widths.")

(defun gemini-cli--eat-adjust-process-window-size-advice (orig-fun &rest args)
  "Advice for `eat--adjust-process-window-size' to only signal on width change.

Returns the size returned by ORIG-FUN only when the width of any Gemini
window has changed, not when only the height has changed. This prevents
unnecessary terminal reflows when only vertical space changes.

ARGS is passed to ORIG-FUN unchanged."
  (when (and eat-terminal (eat-term-live-p eat-terminal))
    ;; Call the original function first
    (let ((result (apply orig-fun args)))
      ;; Check all windows for Gemini buffers
      (let ((width-changed nil))
        (dolist (window (window-list))
          (let ((buffer (window-buffer window)))
            (when (and buffer (string-match-p "^\\*gemini" (buffer-name buffer)))
              (let ((current-width (window-width window))
                    (stored-width (gethash window gemini-cli--window-widths)))
                ;; Check if this is a new window or if width changed
                (when (or (not stored-width) (/= current-width stored-width))
                  (setq width-changed t)
                  ;; Update stored width
                  (puthash window current-width gemini-cli--window-widths))))))
        ;; Return result only if a Gemini window width changed, otherwise nil
        (if width-changed result nil)))))

(defun gemini-cli (&optional arg)
  "Start Gemini in an eat terminal and enable `gemini-cli-mode'.

If current buffer belongs to a project start Gemini in the project's
root directory. Otherwise start in the directory of the current buffer
file, or the current value of `default-directory' if no project and no
buffer file.

With single prefix ARG (\\[universal-argument]), switch to buffer after creating.
With double prefix ARG (\\[universal-argument] \\[universal-argument]), continue previous conversation.
With triple prefix ARG (\\[universal-argument] \\[universal-argument] \\[universal-argument]), prompt for the project directory."
  (interactive "P")

  ;; Forward declare variables to avoid compilation warnings
  (require 'eat)

  (let* ((dir (if (equal arg '(64))  ; Triple prefix
                  (read-directory-name "Project directory: ")
                (gemini-cli--directory)))
         (abbreviated-dir (abbreviate-file-name dir))
         (continue (equal arg '(16))) ; Double prefix
         (switch-after (equal arg '(4))) ; Single prefix
         (default-directory dir)
         ;; Check for existing Gemini instances in this directory
         (existing-buffers (gemini-cli--find-gemini-buffers-for-directory dir))
         ;; Determine instance name
         (instance-name (if existing-buffers
                            (read-string (format "Instances already running for %s, new instance name (existing: %s): "
                                                 abbreviated-dir
                                                 (mapconcat (lambda (buf)
                                                              (or (gemini-cli--extract-instance-name-from-buffer-name
                                                                   (buffer-name buf))
                                                                  "default"))
                                                            existing-buffers ", ")))
                          "default"))
         (buffer-name (gemini-cli--buffer-name instance-name))
         (trimmed-buffer-name (string-trim-right (string-trim buffer-name "\\*") "\\*"))
         (buffer (get-buffer-create buffer-name))
         (program-switches (if continue
                               (append gemini-cli-program-switches '("--continue"))
                             gemini-cli-program-switches)))
    ;; Start the eat process
    (with-current-buffer buffer
      (cd dir)
      (setq-local eat-term-name gemini-cli-term-name)

      ;; Turn off shell integration, as we don't need it for Gemini
      (setq-local eat-enable-directory-tracking t
                  eat-enable-shell-command-history nil
                  eat-enable-shell-prompt-annotation nil)
      
      ;; Conditionally disable scrollback truncation
      (when gemini-cli-never-truncate-gemini-buffer
        (setq-local eat-term-scrollback-size nil))

      (let ((process-adaptive-read-buffering nil))
        (condition-case nil
            (apply #'eat-make trimmed-buffer-name gemini-cli-program nil program-switches)
          (error
           (error "error starting gemini")
           (signal 'gemini-start-error "error starting gemini"))))

      ;; Set eat repl faces to inherit from gemini-cli-repl-face
      (gemini-cli--setup-repl-faces)

      ;; Add advice to only nottify gemini on window width changes, to avoid uncessary flickering
      (advice-add 'eat--adjust-process-window-size :around #'gemini-cli--eat-adjust-process-window-size-advice)

      ;; Set our custom synchronize scroll function
      (setq-local eat--synchronize-scroll-function #'gemini-cli--synchronize-scroll)

      ;; Add window configuration change hook to keep buffer scrolled to bottom
      (add-hook 'window-configuration-change-hook #'gemini-cli--on-window-configuration-change nil t)

      ;; fix wonky initial terminal layout that happens sometimes if we show the buffer before gemini is ready
      (sleep-for gemini-cli-startup-delay)

      ;; Add cleanup hook to remove directory mappings when buffer is killed
      (add-hook 'kill-buffer-hook #'gemini-cli--cleanup-directory-mapping nil t)

      ;; run start hooks and show the gemini buffer
      (run-hooks 'gemini-cli-start-hook)
      (display-buffer buffer))
    (when switch-after
      (switch-to-buffer buffer))))

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
        (when (and (equal arg '(16)) selected-buffer)  ; Only switch buffer with C-u C-u
          (switch-to-buffer selected-buffer))))))

;;;###autoload
(defun gemini-cli-toggle ()
  "Show or hide the Gemini window.

If the Gemini buffer doesn't exist, create it."
  (interactive)
  (let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
    (if gemini-cli-buffer
        (if (get-buffer-window gemini-cli-buffer)
            (delete-window (get-buffer-window gemini-cli-buffer))
          (display-buffer gemini-cli-buffer))
      (gemini-cli--show-not-running-message))))

;;;###autoload
(defun gemini-cli-switch-to-buffer (&optional arg)
  "Switch to the Gemini buffer if it exists.

With prefix ARG, show all Gemini instances across all directories."
  (interactive "P")
  (if arg
      ;; With prefix arg, show all Gemini instances
      (let ((all-buffers (gemini-cli--find-all-gemini-buffers)))
        (cond
         ((null all-buffers)
          (gemini-cli--show-not-running-message))
         ((= (length all-buffers) 1)
          ;; Only one buffer, just switch to it
          (switch-to-buffer (car all-buffers)))
         (t
          ;; Multiple buffers, let user choose
          (let ((selected-buffer (gemini-cli--select-buffer-from-choices
                                  "Select Gemini instance: "
                                  all-buffers)))
            (when selected-buffer
              (switch-to-buffer selected-buffer))))))
    ;; Without prefix arg, use normal behavior
    (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
        (switch-to-buffer gemini-cli-buffer)
      (gemini-cli--show-not-running-message))))

;;;###autoload
(defun gemini-cli-kill (&optional arg)
  "Kill Gemini process and close its window.

With prefix ARG, kill ALL Gemini processes across all directories."
  (interactive "P")
  (if arg
      ;; Kill all Gemini instances
      (let ((all-buffers (gemini-cli--find-all-gemini-buffers)))
        (if all-buffers
            (let* ((buffer-count (length all-buffers))
                   (plural-suffix (if (= buffer-count 1) "" "s")))
              (when (yes-or-no-p (format "Kill %d Gemini instance%s? " buffer-count plural-suffix))
                (dolist (buffer all-buffers)
                  (gemini-cli--kill-buffer buffer))
                (message "%d Gemini instance%s killed" buffer-count plural-suffix)))
          (gemini-cli--show-not-running-message)))
    ;; Kill single instance
    (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
        (when (yes-or-no-p "Kill Gemini instance? ")
          (gemini-cli--kill-buffer gemini-cli-buffer)
          (message "Gemini instance killed"))
      (gemini-cli--show-not-running-message))))

;;;###autoload
(defun gemini-cli-send-command (cmd &optional arg)
  "Read a Gemini command from the minibuffer and send it.

With prefix ARG, switch to the Gemini buffer after sending CMD."
  (interactive "sGemini command: \nP")
  (let ((selected-buffer (gemini-cli--do-send-command cmd)))
    (when (and arg selected-buffer)
      (switch-to-buffer selected-buffer))))

;;;###autoload
(defun gemini-cli-send-command-with-context (cmd &optional arg)
  "Read a Gemini command and send it with current file and line context.

If region is active, include region line numbers.
With prefix ARG, switch to the Gemini buffer after sending CMD."
  (interactive "sGemini command: \nP")
  (let* ((file-name (gemini-cli--get-buffer-file-name))
         (line-info (if (use-region-p)
                        (format "Lines: %d-%d"
                                (line-number-at-pos (region-beginning))
                                (line-number-at-pos (region-end)))
                      (format "Line: %d" (line-number-at-pos))))
         (cmd-with-context (if file-name
                               (format "%s\nContext: File: %s, %s"
                                       cmd
                                       file-name
                                       line-info)
                             cmd)))
    (let ((selected-buffer (gemini-cli--do-send-command cmd-with-context)))
      (when (and arg selected-buffer)
        (switch-to-buffer selected-buffer)))))

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
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (eat-term-send-string eat-terminal (kbd "ESC"))
        (display-buffer gemini-cli-buffer))
    (gemini-cli--show-not-running-message)))

;;;###autoload
(defun gemini-cli-cycle-mode ()
  "Send Shift-Tab to Gemini to cycle between modes.

Gemini uses Shift-Tab to cycle through:
- Default mode
- Auto-accept edits mode
- Plan mode"
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (eat-term-send-string eat-terminal "\e[Z")
        (display-buffer gemini-cli-buffer))
    (gemini-cli--show-not-running-message)))

(defun gemini-cli-fork ()
  "Jump to a previous conversation by invoking the Gemini fork command.

Sends <escape><escape> to the Gemini CLI REPL."
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (eat-term-send-string eat-terminal "")
        (display-buffer gemini-cli-buffer))
    (error "Gemini is not running")))

;;;###autoload
(defun gemini-cli-fix-error-at-point (&optional arg)
  "Ask Gemini to fix the error at point.

Gets the error message, file name, and line number, and instructs Gemini
to fix the error. Supports both flycheck and flymake error systems, as well
as any system that implements help-at-pt.

With prefix ARG, switch to the Gemini buffer after sending."
  (interactive "P")
  (let* ((error-text (gemini-cli--format-errors-at-point))
         (file-name (gemini-cli--get-buffer-file-name)))
    (if (string= error-text "No errors at point")
        (message "No errors found at point")
      (let ((command (format "Fix this error in %s:\nDo not run any external linter or other program, just fix the error at point using the context provided in the error message: <%s>"
                             file-name error-text)))
        (let ((selected-buffer (gemini-cli--do-send-command command)))
          (when (and arg selected-buffer)
            (switch-to-buffer selected-buffer)))))))

;;;###autoload
(defun gemini-cli-read-only-mode ()
  "Enter read-only mode in Gemini buffer with visible cursor.

In this mode, you can interact with the terminal buffer just like a
regular buffer. This mode is useful for selecting text in the Gemini
buffer. However, you are not allowed to change the buffer contents or
enter Gemini commands.

Use `gemini-cli-exit-read-only-mode' to switch back to normal mode."
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (eat-emacs-mode)
        (setq-local eat-invisible-cursor-type gemini-cli-read-only-mode-cursor-type)
        (eat--set-cursor nil :invisible)
        (message "Gemini read-only mode enabled"))
    (gemini-cli--show-not-running-message)))

;;;###autoload
(defun gemini-cli-exit-read-only-mode ()
  "Exit read-only mode and return to normal mode (eat semi-char mode)."
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (eat-semi-char-mode)
        (setq-local eat-invisible-cursor-type nil)
        (eat--set-cursor nil :invisible)
        (message "Gemini semi-char mode enabled"))
    (gemini-cli--show-not-running-message)))

;;;###autoload
(defun gemini-cli-toggle-read-only-mode ()
  "Toggle between read-only mode and normal mode.

In read-only mode you can interact with the terminal buffer just like a
regular buffer. This mode is useful for selecting text in the Gemini
buffer. However, you are not allowed to change the buffer contents or
enter Gemini commands."
  (interactive)
  (if-let ((gemini-cli-buffer (gemini-cli--get-or-prompt-for-buffer)))
      (with-current-buffer gemini-cli-buffer
        (if eat--semi-char-mode
            (gemini-cli-read-only-mode)
          (gemini-cli-exit-read-only-mode)))
    (gemini-cli--show-not-running-message)))

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
