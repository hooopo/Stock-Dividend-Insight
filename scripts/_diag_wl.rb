require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('..', __dir__))
load File.expand_path('../scripts/gt3_pages.rb', __dir__)

entry = whitelist_entry_for('601088')
puts "whitelist_entry_for('601088') = " + entry.inspect
puts "WHITELIST_BY_CODE 大小: #{WHITELIST_BY_CODE.size}"
