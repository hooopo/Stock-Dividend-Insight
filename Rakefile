require 'active_record'
require 'dotenv/load'
require 'logger'

# 数据库配置
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
ActiveRecord::Base.logger = Logger.new(STDOUT)

desc "Run migrations"
task :migrate do
  ActiveRecord::MigrationContext.new('db/migrate').migrate
end

desc "Rollback migration"
task :rollback do
  ActiveRecord::MigrationContext.new('db/migrate').rollback
end

desc "Setup database (create and migrate)"
task :setup => [:create, :migrate]

task :create do
  require 'uri'
  uri = URI.parse(ENV['DATABASE_URL'])
  dbname = uri.path[1..-1].split('?').first # 确保只获取数据库名，排除查询参数
  
  # 建立到 postgres 默认数据库的连接以尝试创建新数据库
  # 使用 URI 对象的 dup 来修改路径而不破坏原始 URL
  create_db_uri = uri.dup
  create_db_uri.path = '/postgres'
  
  ActiveRecord::Base.establish_connection(create_db_uri.to_s)
  begin
    ActiveRecord::Base.connection.create_database(dbname)
    puts "Database '#{dbname}' created."
  rescue ActiveRecord::DatabaseAlreadyExists
    puts "Database '#{dbname}' already exists."
  rescue => e
    puts "Note: Could not create database via script (#{e.message})."
    puts "If you are using a managed database like Neon, the database should be created via their console."
  end
  # 重新连回目标数据库
  ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])
end
