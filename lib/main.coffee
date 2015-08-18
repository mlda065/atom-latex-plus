fs = require 'fs'
path = require 'path'
readdirp = require 'readdirp'
{Disposable, CompositeDisposable} = require 'atom'

ProcessManager = require './process_manager'
MessageManager = require './message_manager'
StatusBarManager = require './status_bar_manager'
Latexmk = require './latexmk'
LogParser = require './log_parser'

class TeXlicious
  config:
    texPath:
      title: 'TeX Path'
      description: "Location of your custom TeX installation bin."
      type: 'string'
      default: ''
      order: 1
    texInputs:
      title: 'TeX Packages'
      description: "Location of your custom TeX packages directory."
      type: 'string'
      default: ''
      order: 3
    bibtexEnabled:
      title: 'Enable BibTeX'
      type: 'boolean'
      default: false
      order: 5
    shellEscapeEnabled:
      title: 'Enable Shell Escape'
      type: 'boolean'
      default: false
      order: 6

  constructor: ->
    @processManager = new ProcessManager()
    @messageManager = new MessageManager()
    @statusBarManager = new StatusBarManager()
    @latexmk = new Latexmk()
    @logParser = new LogParser()

    @disposables = new CompositeDisposable
    @errorMarkers = [] # TODO: Make this a composite disposable.

  activate: (state) ->
    atom.commands.add 'atom-text-editor', 'texlicious:compile': =>
      @loadProject(@compile)


  deactivate: ->
    @messageManager.destroy()
    @statusBarManager.destroy()

  loadProject: (callback) ->
    editor = atom.workspace.getActiveTextEditor()
    file = editor.getPath()

    # if the current file is not in the current projectRoot, find the new
    # project's settings
    if file.indexOf(@projectRoot) > -1
      callback()
      return

    for directory in atom.project.getPaths()
     if file.indexOf(directory) > -1
      readdirp({ root: directory, depth: 1, entryType: 'files', fileFilter: 'tex.json' })
      .on 'data', (config) =>
        @projectRoot = directory

        fs.watchFile config.fullPath, (curr, prev) =>
          if curr.mtime != prev.mtime
            @setProject(config.fullPath, callback)

        @setProject(config.fullPath, callback)
      .on 'end', () =>
        unless @projectRoot?
          atom.notifications.addError("The project \'#{path.basename directory.getPath()}\' is not a valid project.")

  setProject: (config, callback) ->
    fs.readFile config, (err, json) =>
      data = JSON.parse(json)
      @statusBarManager.project = data.project
      @root = path.join(@projectRoot, data.root)
      unless path.extname(@root) is '.tex'
        atom.notifications.addInfo("The project root does not have the extension '.tex'.")
        return

      fs.exists @root , (exists) =>
        unless exists
          atom.notifications.addError("The project configuration file must be defined in #{path.basename @projectRoot}.")
          return

        # TODO: check if the program is valid
        @program = data.program
        @output = path.join(@projectRoot, data.output)

        @statusBarManager.update('ready')
        callback()

  consumeStatusBar: (statusBar) ->
    @statusBarManager.initialize(statusBar)
    @statusBarManager.attach()
    @disposables.add new Disposable =>
      @statusBarManager.detach()

  makeArgs: ->
    args = []

    latexmkArgs = {
      default: '-interaction=nonstopmode -f -cd -pdf -file-line-error'
    }

    latexmkArgs.bibtex = '-bibtex' if atom.config.get('texlicious.bibtexEnabled')
    latexmkArgs.shellEscape = '-shell-escape' if atom.config.get('texlicious.shellEscapeEnabled')

    args.push latexmkArgs.default
    if latexmkArgs.shellEscape?
      args.push latexmkArgs.shellEscape
    if latexmkArgs.bibtex?
      args.push latexmkArgs.bibtex
    unless @program == "pdflatex"
      args.push "-#{@program}"
    args.push "-outdir=\"#{@output}\""
    args.push "\"#{@root}\""

    args

  # TODO: Update editor gutter when file is opened.
  updateGutter: (errors) =>
    @messageManager.update(errors)
    editors =  atom.workspace.getTextEditors()

    for error in errors
      for editor in editors
        errorFile = path.basename error.file
        if errorFile == path.basename editor.getPath()
          row = parseInt error.line - 1
          column = editor.buffer.lineLengthForRow(row)
          range = [[row, 0], [row, column]]
          marker = editor.markBufferRange(range, invalidate: 'touch')
          decoration = editor.decorateMarker(marker, {type: 'line-number', class: 'gutter-red'})
          @errorMarkers.push marker

  compile: =>
    @statusBarManager.update('compile')

    # save all modified tex files before compiling
    for pane in atom.workspace.getPanes()
      pane.saveItems()

    args = @makeArgs()
    options = @processManager.options()
    proc = @latexmk.make args, options, (exitCode) =>
      switch exitCode
        when 0
          @statusBarManager.update('ready')
          @messageManager.update(null)
          marker.destroy() for marker in @errorMarkers
        else
          @statusBarManager.update('error')
          log = path.join(@output, path.basename(@root).split('.')[0] + '.log')
          @logParser.parseLogFile(log, @updateGutter)

module.exports = new TeXlicious()
