opts :download_file do
  summary "Download file from guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to download from", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :local_path, "Local file to download to", :required => true, :type => :string
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

rvc_alias :download_file
rvc_alias :download_file, :download

def download_file vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  opts[:permissions] = opts[:permissions].to_i(8) if opts[:permissions]

  if opts[:password].nil? or opts[:password].empty?
    opts[:password] = ask("password: ") { |q| q.echo = false }
  end

  auth = VIM.NamePasswordAuthentication(
    :username => opts[:username],
    :password => opts[:password],
    :interactiveSession => opts[:interactive_session]
  )

  download_url = fileManager.
    InitiateFileTransferFromGuest(
      :vm => vm,
      :auth => auth,
      :guestFilePath => opts[:guest_path]
    ).url

  download_uri = URI.parse(download_url.gsub /http(s?):\/\/\*:[0-9]*/, "")
  download_path = "#{download_uri.path}?#{download_uri.query}"

  http_download vm._connection, download_path, opts[:local_path]
end


opts :upload_file do
  summary "Upload file to guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :group_id, "Group ID of file", :type => :int
  opt :guest_path, "Path in guest to upload to", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :local_path, "Local file to upload", :required => true, :type => :string
  opt :overwrite, "Overwrite file", :default => false, :type => :bool
  opt :owner_id, "Owner ID of file", :type => :int
  opt :password, "Password in guest", :type => :string
  opt :permissions, "Permissions of file", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

rvc_alias :upload_file
rvc_alias :upload_file, :upload

def upload_file vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  opts[:permissions] = opts[:permissions].to_i(8) if opts[:permissions]

  if opts[:password].nil? or opts[:password].empty?
    opts[:password] = ask("password: ") { |q| q.echo = false }
  end

  auth = VIM.NamePasswordAuthentication(
    :username => opts[:username],
    :password => opts[:password],
    :interactiveSession => opts[:interactive_session]
  )

  file = File.new(opts[:local_path], 'rb')

  upload_url = fileManager.
    InitiateFileTransferToGuest(
      :vm => vm,
      :auth => auth,
      :guestFilePath => opts[:guest_path],
#      :fileAttributes => {},
      :fileAttributes => VIM.GuestPosixFileAttributes(
        :groupId => opts[:group_id],
        :ownerId => opts[:owner_id],
        :permissions => opts[:permissions]
      ),
      :fileSize => file.size,
      :overwrite => opts[:overwrite]
    )

  upload_uri = URI.parse(upload_url.gsub /http(s?):\/\/\*:[0-9]*/, "")
  upload_path = "#{upload_uri.path}?#{upload_uri.query}"

  http_upload vm._connection, opts[:local_path], upload_path
end


opts :start_program do
  summary "Run program in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :arguments, "Arguments of command", :default => "", :type => :string
  opt :background, "Don't wait for process to finish", :default => false, :type => :bool
  opt :delay, "Interval in seconds", :type => :float, :default => 5.0
  opt :env, "Environment variable(s) to set (e.g. VAR=value)", :multi => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :program_path, "Path to program in guest", :required => true, :type => :string
  opt :timeout, "Timeout in seconds", :type => :int, :default => nil
  opt :username, "Username in guest", :default => "root", :type => :string
  opt :working_directory, "Working directory of the program to run", :type => :string
  conflicts :background, :timeout
  conflicts :background, :delay
end

rvc_alias :start_program
rvc_alias :start_program, :exec

def start_program vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :processManager
  processManager = guestOperationsManager.processManager

  if opts[:password].nil? or opts[:password].empty?
    opts[:password] = ask("password: ") { |q| q.echo = false }
  end

  auth = VIM.NamePasswordAuthentication(
    :username => opts[:username],
    :password => opts[:password],
    :interactiveSession => opts[:interactive_session]
  )

  pid = processManager.
    StartProgramInGuest(
      :vm => vm,
      :auth => auth,
      :spec => VIM.GuestProgramSpec(
        :arguments => opts[:arguments],
        :programPath => opts[:program_path],
        :envVariables => opts[:env],
        :workingDirectory => opts[:working_directory]
      )
    )

  Timeout.timeout opts[:timeout] do
    while true
      processes = processManager.
        ListProcessesInGuest(
          :vm => vm,
          :auth => auth,
          :pids => [pid]
        )
      process = processes.first

      if !process.endTime.nil?
        if process.exitCode != 0
          err "Process failed with exit code #{process.exitCode}"
        end
        break
      elsif opts[:background]
        break
      end

      sleep opts[:delay]
    end
  end
rescue Timeout::Error
  err "Timed out waiting for process to finish."
end
