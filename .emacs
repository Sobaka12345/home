(require 'package)
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/")
             t)
(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

(when (eq system-type 'windows-nt)

  (defun vspshell ()
  "Open a Visual Studio Developer PowerShell."
  (interactive)
  (let ((explicit-shell-file-name
         "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
        (explicit-powershell.exe-args
         '("-NoLogo"
		   "-NoExit"
           "-File"
           "C:\\Program Files\\Microsoft Visual Studio\\18\\Professional\\Common7\\Tools\\Launch-VsDevShell.ps1")))
    (call-interactively #'shell)))

(defun vscmdshell ()
  (interactive)
  (let ((explicit-shell-file-name
         "C:/Windows/System32/cmd.exe")
		(w32-use-native-shell t)
		;;(w32-quote-process-args nil)
		(shell-command-switch "/c")
        (explicit-cmd.exe-args
         '("/k"
           "C:\\Program Files\\Microsoft Visual Studio\\18\\Professional\\VC\\Auxiliary\\Build\\vcvars64.bat")))
    (shell "*VS Command Prompt*")))
  )

(setq pop-up-frames nil)

(setq display-buffer-alist
      '((".*"
         (display-buffer-reuse-window
          display-buffer-same-window))))

;; Exception to the same-window policy above, for dap-mode's preLaunchTask
;; compile-log buffers only: with the blanket policy, these always take
;; over the current (often sole) window instead of splitting, which makes
;; `dap-debug-run-task' try to `delete-window' the only ordinary window
;; left in the frame once the task finishes -- that errors and aborts the
;; callback that actually starts the debug session, so it silently never
;; launches. Let just these buffers split instead.
(add-to-list 'display-buffer-alist
             '("\\`\\*DAP compilation:"
               (display-buffer-reuse-window
                display-buffer-below-selected)))

;;(use-package eat :ensure t)
;;(add-hook 'eshell-first-time-mode-hook
;;          #'eat-eshell-visual-command-mode)


(use-package multiple-cursors)
;;(use-package vterm :ensure t)

(setq inhibit-startup-message t)
(setq visible-bell nil)
(setq ring-bell-function #'ignore)

(tool-bar-mode -1)
(menu-bar-mode -1)
(scroll-bar-mode -1)
(global-display-line-numbers-mode 1)
(global-visual-line-mode 1)
;; Enable savehist-mode to persist minibuffer history
(setq savehist-file "~/.emacs.d/savehist")
(savehist-mode 1)

;; Optional: Keep more history items
(setq history-length 100)

(setq-default tab-width 4)
(setq-default c-basic-offset 4)

(use-package rg :ensure t)

(if (= (display-color-cells) 16)
    (progn
	  (use-package base16-theme)
	  (load-theme 'base16-default-dark t)
	  (set-face-attribute 'region nil
						  :background "#3c4451"
						  :foreground "#ffffff"))
  (progn
	(use-package solarized-theme)

    (defvar my-light-theme 'solarized-selenized-light)
    (defvar my-dark-theme 'modus-vivendi)

    (defun my-set-theme-by-time ()
      "Set the theme according to the current time."
      (let ((hour (string-to-number (format-time-string "%H"))))
        (mapc #'disable-theme custom-enabled-themes)
        (load-theme (if (and (>= hour 7) (< hour 20))
                        my-light-theme
                      my-dark-theme)
                    t)))
	(my-set-theme-by-time)
	
	(defun switch-theme-by-time ()
	  "Toggle between the configured light and dark themes."
	  (interactive)
	  (let ((next-theme
			 (if (custom-theme-enabled-p my-dark-theme)
				 my-light-theme
			   my-dark-theme)))
		(mapc #'disable-theme custom-enabled-themes)
		(load-theme next-theme t)))
	)
  )

(load-file "~/.emacs.rc/jai-mode.el")
(global-set-key (kbd "<backtab>") 'un-indent-by-removing-4-spaces)
(defun un-indent-by-removing-4-spaces ()
  "remove 4 spaces from beginning of of line"
  (interactive)
  (save-excursion
    (save-match-data
      (beginning-of-line)
      ;; get rid of tabs at beginning of line
      (when (looking-at "^\\s-+")
        (untabify (match-beginning 0) (match-end 0)))
      (when (looking-at "^    ")
        (replace-match "")))))


(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror)

(use-package dap-mode)
(require 'dap-cpptools)
(require 'dap-codelldb)
(require 'dap-launch)
(require 'dap-tasks)
;; dap-ui.el uses the 'breakpoint fringe bitmap for the GUI breakpoint
;; marker (dap-ui--breakpoint-visuals's :bitmap), but never requires
;; gdb-mi.el itself -- that's the library that actually defines it via
;; `define-fringe-bitmap'. Without it the bitmap reference is unresolved
;; and the GUI marker silently doesn't render. This is a pre-existing gap
;; in dap-ui, not something the TTY margin patch below caused -- it never
;; surfaced before because -nw testing goes through the margin path
;; instead of this fringe-bitmap path.
(require 'gdb-mi)
(dap-mode 1)

;; `dap-launch-find-launch-json' calls `(lsp-workspace-root)' with no
;; argument, which falls back to `(buffer-file-name)'. That's nil for
;; buffers not visiting a file -- e.g. the *DAP compilation:...* log
;; buffer used to run preLaunchTask -- so while that buffer is current,
;; dap-mode can't resolve the project root and can't find launch.json
;; at all. Fall back to `default-directory' (which the compile buffer
;; already has set correctly to the project root) when there's no file.
(advice-add 'lsp-workspace-root :around
            (lambda (orig-fn &optional path)
              (funcall orig-fn (or path (buffer-file-name) default-directory))))
(dap-ui-mode 1)

;; `dap-ui--make-overlay' only ever marks a breakpoint/current-line via the
;; fringe, gated behind `(window-system)' -- fringes don't exist in a
;; terminal frame at all, so in `-nw' mode no marker is drawn anywhere.
;; Add a TTY fallback: put the same single-character marker (a "." for a
;; breakpoint, ">" for the current execution line -- see
;; `dap-ui--breakpoint-visuals' / `dap-ui--set-debug-marker') in the left
;; margin instead, which does render in a terminal, right next to
;; `display-line-numbers-mode's column like the fringe marker would in a
;; GUI frame. dap-ui's own :fringe faces are tuned for a small GUI fringe
;; bitmap (e.g. dark green) and read as too dim for a plain margin
;; character in a terminal, so map them to brighter dedicated faces
;; instead of reusing them as-is.
;; :inverse-video gives a solid colored block instead of plain colored
;; text -- a real bigger glyph isn't possible in a terminal (every cell
;; in a TTY grid is a fixed size, there's no per-character font scaling
;; the way a GUI frame has), so this is the closest terminal equivalent.
(defface my-dap-margin-breakpoint-verified
  '((t :foreground "red1" :weight bold :inverse-video t))
  "TTY margin face for a verified (active) breakpoint.")
(defface my-dap-margin-breakpoint-pending
  '((t :foreground "orange" :weight bold :inverse-video t))
  "TTY margin face for a pending/unverified breakpoint.")
(defface my-dap-margin-current-line
  '((t :foreground "cyan" :weight bold :inverse-video t))
  "TTY margin face for the current execution line marker.")
(defun my-dap-margin-face (fringe-face)
  "Map a dap-ui :fringe face to a brighter one for the TTY margin."
  (pcase fringe-face
    ('dap-ui-breakpoint-verified-fringe 'my-dap-margin-breakpoint-verified)
    ('breakpoint-disabled               'my-dap-margin-breakpoint-pending)
    ('dap-ui-compile-errline            'my-dap-margin-current-line)
    (_ fringe-face)))
(defun my-dap-margin-char (fringe-face default-char)
  "Map a dap-ui :fringe face to a TTY margin character.
0 = verified/active breakpoint, O = pending/disabled breakpoint;
anything else (e.g. the current-line marker) keeps its default char."
  (pcase fringe-face
    ('dap-ui-breakpoint-verified-fringe "0")
    ('breakpoint-disabled               "O")
    (_ default-char)))
(defun my-dap-ui--make-overlay (beg end visuals &optional mouse-face buf)
  (let ((ov (make-overlay beg end buf t t)))
    (overlay-put ov 'face          (plist-get visuals :face))
    (overlay-put ov 'mouse-face    mouse-face)
    (overlay-put ov 'dap-ui-overlay t)
    (overlay-put ov 'priority (plist-get visuals :priority))
    (when-let ((char (plist-get visuals :char)))
      (if (window-system)
          (overlay-put ov 'before-string
                       (propertize char 'display
                                   (list 'left-fringe
                                         (plist-get visuals :bitmap)
                                         (plist-get visuals :fringe))))
        (let ((markbuf (or buf (current-buffer))))
          (with-current-buffer markbuf
            (setq-local left-margin-width 1)
            (dolist (win (get-buffer-window-list markbuf nil t))
              (set-window-margins win left-margin-width)))
          (overlay-put ov 'before-string
                       (propertize " " 'display
                                   (list '(margin left-margin)
                                         (propertize (my-dap-margin-char (plist-get visuals :fringe) char)
                                                     'face
                                                     (my-dap-margin-face (plist-get visuals :fringe)))))))))
    ov))
(advice-add 'dap-ui--make-overlay :override #'my-dap-ui--make-overlay)

;; Work around a dap-mode bug: breakpoints restored from
;; `dap-breakpoints-file' at startup (via `dap--after-initialize', just
;; run by `dap-mode' above) only get a live `:marker' for files whose
;; buffer is *already open* at that moment -- none are, this early.
;; Any breakpoint left marker-less then crashes the first time
;; anything calls `dap--switch-to-session' (e.g. clicking a stack
;; frame in the call-stack window), via `dap--buffers-w-breakpoints'
;; calling `marker-buffer' on a nil marker: (wrong-type-argument
;; markerp nil). Fix: eagerly visit every file with a persisted
;; breakpoint so its marker gets established up front.
(defun my-dap-materialize-breakpoint-markers ()
  (maphash (lambda (file file-breakpoints)
             (when (file-exists-p file)
               (find-file-noselect file)
               (dap--set-breakpoints-in-file file file-breakpoints)))
           (dap--get-breakpoints)))
(my-dap-materialize-breakpoint-markers)

;; keep focus in the call-stack (*dap-ui-sessions*) window when
;; clicking a stack frame or thread there -- the source location still
;; opens/updates in its window, but the selected window doesn't change,
;; so browsing several frames in a row doesn't keep stealing focus.
;;
;; Clicking a THREAD (`dap-ui-thread-select') needs more than just
;; wrapping the command: it sends an async "stackTrace" DAP request
;; and only calls `dap--go-to-stack-frame' (the function that actually
;; steals focus) from inside the response callback, which fires well
;; after `save-selected-window's protection here has already ended.
;; So also advise `dap--go-to-stack-frame' itself, gated by a flag set
;; when browsing starts and cleared shortly after (on the next idle
;; moment, by which point any fast local-process async response has
;; long arrived) so it doesn't linger and affect a later, unrelated
;; natural breakpoint stop.
(defvar my-dap-preserve-focus-for-next-jump nil)

(advice-add 'dap--go-to-stack-frame :around
            (lambda (orig-fn &rest args)
              (if my-dap-preserve-focus-for-next-jump
                  (save-selected-window (apply orig-fn args))
                (apply orig-fn args))))

(dolist (fn '(dap-ui-select-stack-frame dap-ui-thread-select))
  (advice-add fn :around
              (lambda (orig-fn &rest args)
                (setq my-dap-preserve-focus-for-next-jump t)
                (unwind-protect
                    (save-selected-window (apply orig-fn args))
                  (run-with-idle-timer
                   0 nil (lambda () (setq my-dap-preserve-focus-for-next-jump nil)))))))

;; don't let the call-stack tree collapse on every refresh (stepping,
;; continuing, clicking a frame -- anything that runs
;; `dap-session-changed-hook'/`dap-stack-frame-changed-hook', both of
;; which call `dap-ui-sessions--refresh'). By default that does a full
;; `treemacs-update-node' from the tree root, which resets every node
;; back to closed with no way to opt out via that call's arguments.
;; Replace it with a version that records which node paths are
;; currently expanded (and the cursor line) beforehand, then restores
;; both after the refresh completes.
(defun my-dap--collect-expanded-paths ()
  (let (paths)
    (maphash (lambda (key node)
               (when (and (not (equal key '(lsp-treemacs-generic-root)))
                          (treemacs-dom-node->position node)
                          (ignore-errors (treemacs-is-node-expanded? (treemacs-dom-node->position node))))
                 (push key paths)))
             treemacs-dom)
    paths))

(defun my-dap--restore-expanded-paths (paths)
  (dolist (path (sort (copy-sequence paths) (lambda (a b) (< (length a) (length b)))))
    (ignore-errors
      (let ((btn (treemacs-goto-node path)))
        (when (and btn (not (treemacs-is-node-expanded? btn)))
          (treemacs-TAB-action))))))

(defun my-dap--refresh-preserving-expand-1 ()
  (let ((paths (my-dap--collect-expanded-paths))
        (line (line-number-at-pos)))
    (lsp-treemacs-generic-refresh)
    (my-dap--restore-expanded-paths paths)
    (goto-char (point-min))
    (forward-line (1- line))))

(defun my-dap-sessions-refresh-preserving-expand (&rest _)
  (lsp-treemacs-wcb-unless-killed dap-ui--sessions-buffer
    ;; use `with-selected-window' (not just `with-current-buffer') so
    ;; the window actually showing this buffer has its own window-point
    ;; updated -- otherwise, if some other window is selected at the
    ;; time (e.g. mid-jump to a source location), the sessions window's
    ;; displayed scroll position doesn't follow the buffer's point and
    ;; needs manual scrolling to find.
    (if-let ((win (get-buffer-window (current-buffer))))
        (with-selected-window win
          (my-dap--refresh-preserving-expand-1))
      (my-dap--refresh-preserving-expand-1))))

(advice-add 'dap-ui-sessions--refresh :override #'my-dap-sessions-refresh-preserving-expand)

;; trim dap-mode's auto-shown windows down to just locals + watch
;; expressions; drop the floating controls posframe, hover tooltips,
;; and the auto-popping output buffer
;; `sessions' is dap-ui's call-stack view (Session > Threads > Stack
;; Frames); it's already docked to the right (slot 3, next to locals
;; and expressions) via `dap-ui-buffer-configurations', which -- since
;; `window-sides-vertical' is nil by default -- ends up to the right
;; of the bottom-docked adapter log window.
(setq dap-auto-configure-features '(locals expressions sessions))
(setq dap-auto-show-output 1)
(dap-auto-configure-mode 1)

;; the CodeLLDB adapter process's own log (mode-line "Debug Adapter",
;; buffer name "* ... log*") isn't covered by dap-auto-show-output --
;; it's started via `compilation-start' with no size limit, so it
;; defaults to a plain 50/50 window split. Keep it visible (it's where
;; real adapter startup errors show up) but confine it to a small
;; bottom side window instead.
(add-to-list 'display-buffer-alist
             '((lambda (buffer-name _action)
                 (with-current-buffer buffer-name
                   (derived-mode-p 'dap-server-log-mode)))
               (display-buffer-in-side-window)
               (side . bottom)
               (slot . 6)
               (window-height . 0.2)))

(desktop-save-mode 1)
(savehist-mode 1)

(global-set-key (kbd "C-c C-<left>")  'windmove-left)
(global-set-key (kbd "C-c C-<right>") 'windmove-right)
(global-set-key (kbd "C-c C-<up>")    'windmove-up)
(global-set-key (kbd "C-c C-<down>")  'windmove-down)

(repeat-mode 1)
(defvar windmove-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<left>")  'windmove-left)
    (define-key map (kbd "<right>") 'windmove-right)
    (define-key map (kbd "<up>")    'windmove-up)
    (define-key map (kbd "<down>")  'windmove-down)
    map)
  "Keymap for repeating windmove commands via `repeat-mode'.
After `C-c <left>' (etc.) once, bare arrow keys repeat window
switching until some other command is invoked.")
(put 'windmove-left 'repeat-map 'windmove-repeat-map)
(put 'windmove-right 'repeat-map 'windmove-repeat-map)
(put 'windmove-up 'repeat-map 'windmove-repeat-map)
(put 'windmove-down 'repeat-map 'windmove-repeat-map)

(defvar my-dap-active-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<f5>") #'dap-continue)
    (define-key map (kbd "<f10>") #'dap-next)
    (define-key map (kbd "<f11>") #'dap-step-in)
    (define-key map (kbd "S-<f11>") #'dap-step-out)
    (define-key map (kbd "<f12>") #'dap-ui-mode)
    (define-key map (kbd "<f9>") #'dap-breakpoint-toggle)
    map)
  "Keymap active only while a dap-mode debug session is running.")

(define-minor-mode my-dap-active-mode
  "Minor mode providing debugging hotkeys.
Turned on/off automatically as dap-mode sessions start/end; see
`dap-session-created-hook' and `dap-terminated-hook'."
  :global t
  :keymap my-dap-active-keymap)

(defun my-dap-active-mode-enable (&rest _)
  (my-dap-active-mode 1))

(defun my-dap-active-mode-disable (&rest _)
  ;; a terminated session doesn't mean debugging has
  ;; stopped altogether if another session is still up
  (unless (seq-some #'dap--session-running (dap--get-sessions))
    (my-dap-active-mode -1)))

(add-hook 'dap-session-created-hook #'my-dap-active-mode-enable)
(add-hook 'dap-terminated-hook #'my-dap-active-mode-disable)

(use-package corfu
  :ensure t
  :init
  (global-corfu-mode)
  :custom
  (corfu-auto nil)  ; disable auto-popup
  ;;(corfu-auto t)                 ;; Enable auto-completion as you type
  (corfu-quit-no-match 'separator)) ;; Quit cleanly if no match
(define-key corfu-mode-map (kbd "C-<tab>") 'completion-at-point)

(use-package corfu-terminal
  :ensure t
  :after corfu
  :config
  (corfu-terminal-mode +1)
  ;; Push the popup one extra line below the point row. corfu-terminal has
  ;; no vertical-offset option of its own; every placement goes through
  ;; `popon-x-y-at-posn', so shift its returned row here.
  (advice-add 'popon-x-y-at-posn :filter-return
              (lambda (xy) (when xy (cons (car xy) (1+ (cdr xy)))))))

;; 2. Enable Eglot (Built-in) for your programming language
(use-package eglot
  :hook ((python-mode . eglot-ensure)   ;; Hook to your languages
	 (rust-mode   . eglot-ensure)
	 (c-mode      . eglot-ensure)
	 (c++-mode    . eglot-ensure)
	 (glsl-mode   . eglot-ensure))
  :config
  ;; never let clangd auto-insert #include lines on completion
  (add-to-list 'eglot-server-programs
               '((c++-mode c-mode) . ("clangd" "--header-insertion=never"))))

(setq eglot-ignored-server-capabilities
      '(:documentOnTypeFormattingProvider))

;; bridge kill-ring <-> system clipboard when running emacs -nw (uses the
;; xclip binary, which talks to the X11 clipboard specifically -- not
;; Wayland, macOS, or Windows)
(defun my-x11-linux-p ()
  "Non-nil if running on Linux under an X11 session (not Wayland)."
  (and (eq system-type 'gnu/linux)
       (getenv "DISPLAY")
       (not (getenv "WAYLAND_DISPLAY"))))
;; Guard outside `use-package' itself, not via `:if' -- `:if' still let
;; `:ensure' attempt installation on non-matching systems (broke on
;; Windows), since apparently it doesn't gate the ensure step. Wrapping
;; the whole form means `use-package'/`:ensure' never runs at all
;; elsewhere.
(when (and (not (display-graphic-p)) (my-x11-linux-p))
  (use-package xclip
    :ensure t
    :config
    (xclip-mode 1)))

;; C-s: seed isearch with the active region's text, if it's a single-line region
(defun my-isearch-yank-string-preserve-case (string)
  "Pull STRING into the search string as-is, without `isearch-yank-string''s downcasing."
  (when isearch-regexp (setq string (regexp-quote string)))
  (setq isearch-yank-flag t)
  (isearch-process-search-string
   string (mapconcat #'isearch-text-char-description string "")))

(defun my-isearch-forward-or-region (&optional regexp-p no-recursive-edit)
  (interactive "P\np")
  (if (and (use-region-p)
           (= (line-number-at-pos (region-beginning))
              (line-number-at-pos (region-end))))
      (let ((string (buffer-substring-no-properties (region-beginning) (region-end))))
        (deactivate-mark)
        (isearch-mode t regexp-p nil (not no-recursive-edit))
        (my-isearch-yank-string-preserve-case string))
    (isearch-forward regexp-p no-recursive-edit)))

(global-set-key (kbd "C-s") #'my-isearch-forward-or-region)

;; choose current line and save it to the copy buffer
(defun my-copy-file-line ()
  (interactive)
  (let ((text (format "%s:%d"
                      (or (buffer-file-name) (buffer-name))
                      (line-number-at-pos))))
    (kill-new text)
    (message "%s" text)))

(global-set-key (kbd "C-c l") #'my-copy-file-line)
