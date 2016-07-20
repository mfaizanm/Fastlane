require 'fastlane' # TODO: Remove

module Danger
  # A danger plugin: https://github.com/danger/danger
  class DangerScreenGrid < Plugin
    def run
      require 'snapshot'
      require 'aws-sdk'
      require 'digest/md5'

      data = collect
      screens_per_row = 4

      # We don't use `markdown` calls directly
      # As we also want to publish this as HTML file
      # on S3 for a better display
      html = []

      data.each do |language, language_content|
        html << "<h3>#{language}</h3>"

        html << "<table>"
        language_content.each do |device_type, device_content|
          html << "<tr><th colspan='#{screens_per_row}'>"
          html << beautiful_device_name(device_type)
          html << "</th></tr>"
          html << "<tr>"
          device_content.each_with_index do |url, index|
            html << "<td width='#{(100 / screens_per_row).round}%'>"
            html << (url ? "<img src='#{url}' />" : "upload failed")
            html << "</td>"
            html << "</tr><tr>" if index % screens_per_row == screens_per_row - 1
          end
          html << "</tr>"
        end
        html << "</table>"
      end
      markdown(html.join("\n"))
    end

    private

    def s3_bucket
      @s3_bucket ||= s3_client.bucket("fxplayground" || ENV["AWS_BUCKET_NAME"])
    end

    def s3_client
      @s3_client ||= Aws::S3::Resource.new(
        access_key_id: ENV['AWS_ACCESS_KEY_ID'] || s3_access_key,
        secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'] || s3_secret_access_key,
        region: "eu-central-1" || ENV['AWS_REGION'] || s3_region
      )
    end

    # => {"en-US"=>
    #   {"iPhone4s"=>
    #     ["https://fxplayground.s3.eu-central-1.amazonaws.com/screen_grid/a5f9190c55469c5c07f2b6f7102b7d16.png?X-Amz-Algorithm=...",
    #      "https://fxplayground.s3.eu-central-1.amazonaws.com/screen_grid/f3f71a54072ccb5642ec544a44c5fd18.png?X-Amz-Algorithm=...",
    #      "https://fxplayground.s3.eu-central-1.amazonaws.com/screen_grid/afe6b4b9fe66ce609dec64a77e4d0713.png?X-Amz-Algorithm=..."],
    #    "iPhone5"=>
    #     ["https://fxplayground.s3.eu-central-1.amazonaws.com/screen_grid/57b040e7d8ff35baeb21d7954233b8ce.png?X-Amz-Algorithm=...",
    #    ...
    def collect
      puts "Collecting and uploading screenshots..."
      # screenshots_dir = File.expand_path(Snapshot.config[:output_directory])
      screenshots_dir = "./fastlane/screenshots"
      languages = {}

      Dir[File.join(screenshots_dir, "*")].each do |language_dir|
        next unless File.basename(language_dir).include?("-") # only languages

        language_string = File.basename(language_dir)
        languages[language_string] ||= {}

        language = languages[language_string] # TODO: simplify
        Dir[File.join(language_dir, "*.png")].each do |path|
          device_type = File.basename(path).split("-").first
          language[device_type] ||= []
          language[device_type] << upload_to_s3(path)
        end
      end

      return languages
    end

    def upload_to_s3(path)
      bucket_path = File.join("screen_grid", Digest::MD5.hexdigest(File.read(path)) + ".png")
      obj = s3_bucket.object(bucket_path)
      unless obj.exists?
        # File doesn't exist yet, upload it now
        unless obj.upload_file(path, { content_type: "image/png" })
          FastlaneCore::UI.error("Could not upload file '#{path}'")
          return nil
        end
      end
      return obj.presigned_url(:get, { expires_in: 604_800 }) # That's 7 days
    end

    def beautiful_device_name(str)
      return {
        iphone4s: "iPhone 4s",
        iphone5s: "iPhone 5s",
        iphone6s: "iPhone 6s",
        iphone6splus: "iPhone 6s Plus",
        ipadair: "iPad Air",
        ipadretina: "iPad Retina",
        iphone6: "iPhone 6",
        iphone6plus: "iPhone 6 Plus",
        ipadair2: "iPad Air 2",
        nexus5: "Nexus 5",
        nexus7: "Nexus 7",
        nexus9: "Nexus 9"
      }[str.downcase.to_sym] || str.to_s
    end
  end
end
