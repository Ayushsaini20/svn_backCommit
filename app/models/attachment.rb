# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require "digest/md5"

class Attachment < ActiveRecord::Base
  belongs_to :container, :polymorphic => true
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"
  
  validates_presence_of :container, :filename
	
	def file=(incomming_file)
		unless incomming_file.nil?
			@temp_file = incomming_file
			if @temp_file.size > 0
				self.filename = sanitize_filename(@temp_file.original_filename)
				self.disk_filename = DateTime.now.strftime("%y%m%d%H%M%S") + "_" + self.filename
				self.content_type = @temp_file.content_type
				self.filesize = @temp_file.size
			end
		end
	end
	
	def file
	 nil
	end
	
	# Copy temp file to its final location
	def before_save
		if @temp_file && (@temp_file.size > 0)
			logger.debug("saving '#{self.diskfile}'")
			File.open(diskfile, "wb") do |f| 
				f.write(@temp_file.read)
			end
			self.digest = Digest::MD5.hexdigest(File.read(diskfile))
		end
	end
	
	# Deletes file on the disk
	def after_destroy
		if self.filename?
			File.delete(diskfile) if File.exist?(diskfile)
		end
	end
	
	# Returns file's location on disk
	def diskfile
		"#{$RDM_STORAGE_PATH}/#{self.disk_filename}"
	end
  
  def increment_download
    increment!(:downloads)
  end
	
	# returns last created projects
	def self.most_downloaded
		find(:all, :limit => 5, :order => "downloads DESC")	
	end
	
private
  def sanitize_filename(value)
      # get only the filename, not the whole path
      just_filename = value.gsub(/^.*(\\|\/)/, '')
      # NOTE: File.basename doesn't work right with Windows paths on Unix
      # INCORRECT: just_filename = File.basename(value.gsub('\\\\', '/')) 

      # Finally, replace all non alphanumeric, underscore or periods with underscore
      @filename = just_filename.gsub(/[^\w\.\-]/,'_') 
  end
    
end
