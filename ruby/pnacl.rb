GITSERVER="git@106.109.9.223"
FTPSERVER="ftp://106.109.8.165"

def download file
  ShellTask.run "wget", "#{FTPSERVER}/#{file}"
end

###

class File
  private
  def self.pnacl_root? dir
    dir = File.absolute_path dir
    File.exists?(dir + "/src/native_client/pnacl/build.sh") and \
      File.exists?(dir + "/src/native_client/pnacl/driver/pnacl-translate.py") and \
      Dir.exists?(dir + "/src/native_client/pnacl/git/llvm")
  end

  public
  def self.pnacl_root dir
    return dir if pnacl_root? dir
    return nil if dir == "/"
    return pnacl_root dirname(dir)
  end
end
