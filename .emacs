(setq inhibit-startup-message t)
(setq visible-bell nil)

(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-display-line-numbers-mode 1)

(setq-default tab-width 4)
(setq-default c-basic-offset 4)

;;(load-theme 'modus-vivendi t)
(load-theme 'solarized-selenized-light t)
(setq visible-bell t)

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


(require 'package)
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/")
             t)
(package-initialize)

(setq custom-file (locate-user-emacs-file "custom.el"))
(load custom-file 'noerror)
(require 'dap-cpptools)
(require 'dap-codelldb)
(require 'dap-launch)
(require 'dap-tasks)
(dap-mode 1)
(dap-ui-mode 1)

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
(setq dap-auto-show-output nil)
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
  (corfu-auto t)                 ;; Enable auto-completion as you type
  (corfu-quit-no-match 'separator)) ;; Quit cleanly if no match

;; 2. Enable Eglot (Built-in) for your programming language
(use-package eglot
  :hook ((python-mode . eglot-ensure)   ;; Hook to your languages
	 (rust-mode   . eglot-ensure)
	 (c-mode      . eglot-ensure)
	 (c++-mode    . eglot-ensure)))

