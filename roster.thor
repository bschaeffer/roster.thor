require 'thor'
require 'nokogiri'
require 'open-uri'
require 'yaml'
require 'hirb'

class Float
  def round_to(x)
    (self * 10**x).round / 10**x
  end
end

class Roster < Thor
  include Thor::Actions

  TEAMS_URL   = 'http://espn.go.com/college-football/teams'
  ROSTER_URL  = 'http://espn.go.com/college-football/team/roster/_/id/%d/sort/experience'

  DATA_FILE = File.join(Dir.pwd, 'rosters.yml')

  TEAM_HASH_DEFAULT = {:name => '', :FR => 0, :SO => 0, :JR => 0, :SR => 0}

  #
  # Download
  #
  desc 'download', 'download roster information and save it to a rosters.yml file'
  method_option :quiet  => false
  def download(file='')
    tell "Downloading team/roster information..."
    rosters = load_rosters(load_teams)
    
    tell "Saving file...."
    File.open(DATA_FILE, 'w') { |f|  f.write rosters.to_yaml }
  end

  #
  # Rank
  #
  desc 'rank [SORT]', 'display team ranks based on youth'
  method_option :quiet  => false
  def rank(sort='average')
    if ! File.exists?(DATA_FILE)
      rosters = load_rosters(load_teams)

      if yes?("Would you like us to save the roster data to a file?")
        File.open(DATA_FILE, 'w') { |f| f.write(rosters.to_yaml) }
      end
    else
      rosters = YAML::load(File.open(DATA_FILE))
    end

    info = []
    rosters.each do |r|

      eligibility = ((r[:FR] * 4) + (r[:SO] * 3) + (r[:JR] * 2) + r[:SR]).to_f
      total       = (r[:FR] + r[:SO] + r[:JR] + r[:SR]).to_f

      info.push({
        :name         => r[:name],
        :eligibility  => eligibility,
        :average      => (eligibility / total).round(2)
      })
    end

    sortable = [:name, :eligibility, :average]
    unless sortable.include?(sort.to_sym)
      puts "Invalid sort key. Must be one of: #{sortable.join(', ')}"
      return
    end

    info.sort_by! { |t| t[sort.to_sym] }
    info.reverse!

    puts Hirb::Helpers::AutoTable.render(info, 
      :number => true, 
      :fields => [:name, :eligibility, :average]
    )
  end

  private

    def tell(msg, overwrite=false)
      return if options.quiet?
      if overwrite
        print msg + " " * 20 + "\r"
        $stdout.flush
      else
        $stdout.puts msg
      end
    end

    # Load team names and ids
    def load_teams
      tell "Loading teams..." unless options.quiet?
      teams = []

      doc = Nokogiri::HTML(open(TEAMS_URL))
      div1a = doc.css('div.mod-container > div.span-2').first
      list = div1a.css('div.mod-teams-list-medium ul li')
      
      list.each do |t|
        a_tag = t.search('h5 > a').first
        id = a_tag['href'].match(/_\/id\/([\d]+)\/.+\Z/)[1]
        name = a_tag.content
        teams.push({:id => id, :name => name})
      end

      teams.sort_by { |team|  team[:name] }
    end

    def load_rosters(teams)
      rosters = []
      teams.each do |team|
        tell "Loading roster for #{team[:name]}...", true
        rosters.push load_roster(team)
      end
      tell "All rosters loaded!" + " " * 20
      rosters
    end

    def load_roster(team)
      info = TEAM_HASH_DEFAULT.dup.merge(:name => team[:name])
      team_page = Nokogiri::HTML(open(sprintf(ROSTER_URL, team[:id])))
      team_page.css('td.sortcell').each do |td|
        year = td.content.upcase.to_sym
        info[year] += 1
      end
      info
    end
end