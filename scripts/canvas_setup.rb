user = User.find(1)
account = Account.find(1)
token = AccessToken.create!(:user => user, :developer_key => DeveloperKey.default)
puts token.full_token
account.allow_sis_import=true
account.default_time_zone="Eastern Time (US & Canada)"
account.save
