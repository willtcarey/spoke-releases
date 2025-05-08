#!/usr/bin/env ruby

require 'nokogiri'
require 'digest'
require 'openssl'
require 'fileutils'
require 'json'
require 'base64'
require 'ed25519'

def generate_ed25519_keypair(seed)
  # Decode the base64 seed
  seed_bytes = Base64.decode64(seed)
  
  # Generate Ed25519 keypair from seed
  Ed25519::SigningKey.new(seed_bytes)
end

def get_private_key_from_1password
  # Use 1Password CLI to get the private key
  key_data_json = `op item get "Sparkle signing key" --vault "Private" --format json`
  if $?.exitstatus != 0
    puts "Error: Could not retrieve private key from 1Password"
    puts "Make sure you're signed in to 1Password CLI (op signin)"
    exit 1
  end
  
  # Get the seed from the password field
  seed = JSON.parse(key_data_json)["fields"].find { |field| field["id"] == "password" }["value"]
  
  # Generate Ed25519 keypair from seed
  generate_ed25519_keypair(seed)
end

def generate_ed_signature(file_path)
  signing_key = get_private_key_from_1password
  file_data = File.read(file_path)
  signature = signing_key.sign(file_data)
  Base64.strict_encode64(signature)
end

def generate_appcast_entry(zip_file, version, short_version, min_system_version = "14.2")
  # Get file size
  file_size = File.size(zip_file)
  
  # Generate edSignature using Ed25519 keypair
  ed_signature = generate_ed_signature(zip_file)
  
  # Create XML string for the new item
  xml = <<~XML
        <item>
            <title>#{version}</title>
            <pubDate>#{Time.now.strftime("%a, %d %b %Y %H:%M:%S %z")}</pubDate>
            <sparkle:version>#{version.gsub(/[^\d]/, '')}</sparkle:version>
            <sparkle:shortVersionString>#{short_version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>#{min_system_version}</sparkle:minimumSystemVersion>
            <enclosure url="https://github.com/willtcarey/spoke-releases/releases/download/#{version}/#{File.basename(zip_file)}" length="#{file_size}" type="application/octet-stream" sparkle:edSignature="#{ed_signature}"/>
        </item>
  XML
  
  # Parse the XML string into a Nokogiri node
  Nokogiri::XML::DocumentFragment.parse(xml)
end

def update_appcast(zip_file, version, short_version, min_system_version = "14.2")
  # Read existing appcast
  appcast_path = "appcast.xml"
  doc = Nokogiri::XML(File.read(appcast_path))
  
  # Generate new item
  new_item = generate_appcast_entry(zip_file, version, short_version, min_system_version)
  
  # Add new item to channel
  channel = doc.at_css("channel")
  channel.add_child(new_item)
  
  # Write updated appcast with proper formatting
  File.write(appcast_path, doc.to_xml(indent: 4))
end

# Main script execution
if ARGV.length < 3
  puts "Usage: #{$0} <zip_file> <version> <short_version> [min_system_version]"
  puts "Example: #{$0} Spoke.v3.zip v3 3.0 14.2"
  exit 1
end

zip_file = ARGV[0]
version = ARGV[1]
short_version = ARGV[2]
min_system_version = ARGV[3] || "14.2"

unless File.exist?(zip_file)
  puts "Error: Zip file not found: #{zip_file}"
  exit 1
end

update_appcast(zip_file, version, short_version, min_system_version)
puts "Successfully updated appcast.xml with new release entry" 