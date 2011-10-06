=begin
                  Arachni
  Copyright (c) 2010-2011 Tasos "Zapotek" Laskos <tasos.laskos@gmail.com>

  This is free software; you can copy and distribute and modify
  this program under the term of the GPL v2.0 License
  (See LICENSE file for details)

=end

require Arachni::Options.instance.dir['lib'] + 'module/utilities'
require 'nokogiri'
require Arachni::Options.instance.dir['lib'] + 'nokogiri/xml/node'

module Arachni

#
# Spider class
#
# Crawls the URL in opts[:url] and grabs the HTML code and headers.
#
# @author: Tasos "Zapotek" Laskos
#                                      <tasos.laskos@gmail.com>
#                                      <zapotek@segfault.gr>
# @version: 0.2
#
class Spider

    include Arachni::UI::Output
    include Arachni::Module::Utilities

    #
    #
    # @return [Options]
    #
    attr_reader :opts

    #
    # Sitemap, array of links
    #
    # @return [Array]
    #
    attr_reader :sitemap

    #
    # Code block to be executed on each page
    #
    # @return [Proc]
    #
    attr_reader :on_every_page_blocks

    #
    # Constructor <br/>
    # Instantiates Spider class with user options.
    #
    # @param  [Options] opts
    #
    def initialize( opts )
        @opts = opts

        @sitemap = []
        @on_every_page_blocks = []

        # if we have no 'include' patterns create one that will match
        # everything, like '.*'
        @opts.include =[ Regexp.new( '.*' ) ] if @opts.include.empty?
    end

    #
    # Runs the Spider and passes parsed page to the block
    #
    # @param [Block] block
    #
    # @return [Arachni::Parser::Page]
    #
    def run( &block )
        return if @opts.link_count_limit == 0

        paths = []
        paths << @opts.url.to_s

        visited = []

        opts = {
            :timeout    => nil,
            :remove_id  => true,
            :async      => @opts.spider_first,
            :follow_location => true
        }

        # we need a parser in order to have access to skip() in case
        # there's a redirect that shouldn't be followed
        seed_page = Arachni::HTTP.instance.get( paths[0], opts.merge( :async => false ) ).response
        parser = Parser.new( @opts, seed_page )
        parser.url = paths[0]

        while( !paths.empty? )
            while( !paths.empty? && url = paths.pop )
                next if skip?( url )

                wait_if_paused

                visited << url

                Arachni::HTTP.instance.get( url, opts ).on_complete {
                    |res|

                    next if parser.skip?( res.effective_url )

                    print_line
                    print_status( "[HTTP: #{res.code}] " + res.effective_url )

                    page = Arachni::Parser.new( @opts, res ).run
                    page.url = url_sanitize( res.effective_url )

                    @sitemap |= page.paths
                    paths    |= @sitemap - visited


                    # call the block...if we have one
                    if block
                        exception_jail{
                            block.call( page.clone )
                        }
                    end

                    # run blocks specified later
                    @on_every_page_blocks.each {
                        |block|
                        block.call( page )
                    }

                }

                Arachni::HTTP.instance.run if !@opts.spider_first

                # make sure we obey the link count limit and
                # return if we have exceeded it.
                if( @opts.link_count_limit &&
                    @opts.link_count_limit <= visited.size )
                    Arachni::HTTP.instance.run if @opts.spider_first
                    return @sitemap.uniq
                end


            end

            if @opts.spider_first
                Arachni::HTTP.instance.run
            else
                break
            end

        end

        return @sitemap.uniq
    end

    def skip?( url )
        redundant?( url )
    end

    def redundant?( url )
        @opts.redundant.each_with_index {
            |redundant, i|

            if( url =~ redundant['regexp'] )

                if( @opts.redundant[i]['count'] == 0 )
                    print_verbose( 'Discarding redundant page: \'' + url + '\'' )
                    return true
                end

                print_info( 'Matched redundancy rule: ' +
                redundant['regexp'].to_s + ' for page \'' +
                url + '\'' )

                print_info( 'Count-down: ' + @opts.redundant[i]['count'].to_s )

                @opts.redundant[i]['count'] -= 1
            end
        }
        return false
    end


    def wait_if_paused
        while( paused? )
            ::IO::select( nil, nil, nil, 1 )
        end
    end

    def pause!
        @pause = true
    end

    def resume!
        @pause = false
    end

    def paused?
        @pause ||= false
        return @pause
    end

    #
    # Hook for further analysis of pages, statistics etc.
    #
    # @param [Proc] block code to be executed for every page
    #
    # @return [self]
    #
    def on_every_page( &block )
        @on_every_page_blocks.push( block )
        self
    end

end
end