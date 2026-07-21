(setq inhibit-startup-message t)
(setq visible-bell nil)

(tool-bar-mode -1)
(scroll-bar-mode -1)
(global-display-line-numbers-mode 1)

(load-theme 'modus-vivendi t)

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
    (define-key map (kbd "<f12>") #'dap-ui-mode)
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
