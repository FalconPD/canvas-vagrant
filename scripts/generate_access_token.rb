user = User.find(1)
account = Account.find(1)
token = AccessToken.create!(:user => user, :developer_key => DeveloperKey.default)
puts token.full_token
