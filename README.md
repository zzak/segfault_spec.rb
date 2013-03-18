`ruby --version`
`ruby 2.1.0dev (2013-03-18 trunk 39805) [x86_64-linux]`

Steps to reproduce:

1. `git clone git://github.com/zzak/segfault_spec.rb.git`
2. `bundle install`
3. `bundle exec rspec segfault_spec.rb`
4. repeat #3 until segfault.
