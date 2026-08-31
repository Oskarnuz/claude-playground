module SupportAgent
  # Loads the markdown articles under kb/ and does a naive keyword search.
  # Deliberately simple: the point of the exercise is the agent's decision
  # logic, not retrieval quality.
  class KnowledgeBase
    Article = Struct.new(:id, :title, :category, :sensitive, :tags, :body, keyword_init: true)

    # Raised when the KB backend is unavailable. The agent must treat this as a
    # transient failure: retry, then escalate.
    Unavailable = Class.new(StandardError)

    def self.default
      @default ||= new(Rails.root.join("kb"))
    end

    def initialize(dir)
      @dir = Pathname(dir)
    end

    def articles
      @articles ||= Dir.glob(@dir.join("*.md")).sort.map { |path| parse(File.read(path)) }
    end

    # Returns up to `limit` articles ranked by keyword overlap, each as a Hash
    # ready to hand back to the model as a tool result.
    def search(query, limit: 3)
      raise Unavailable, "knowledge base backend not reachable" if simulate_outage?

      terms = tokenize(query)
      return [] if terms.empty?

      scored = articles.map { |a| [ score(a, terms), a ] }.select { |s, _| s.positive? }
      scored.sort_by { |s, _| -s }.first(limit).map do |score, a|
        {
          id:        a.id,
          title:     a.title,
          category:  a.category,
          sensitive: a.sensitive,
          score:     score,
          excerpt:   a.body.strip
        }
      end
    end

    def find(id)
      articles.find { |a| a.id == id }
    end

    private

    # Test/eval hook: set SUPPORT_AGENT_KB_OUTAGE=1 to force the failure path.
    def simulate_outage?
      ENV["SUPPORT_AGENT_KB_OUTAGE"].to_s == "1"
    end

    def score(article, terms)
      haystack = tokenize("#{article.title} #{article.tags.join(' ')} #{article.body} #{article.category}")
      counts   = Hash.new(0)
      haystack.each { |w| counts[w] += 1 }
      terms.sum do |t|
        weight = article.tags.map { |tag| tokenize(tag) }.flatten.include?(t) ? 3 : 1
        counts[t] * weight
      end
    end

    def tokenize(text)
      text.to_s.downcase.gsub(/[^\p{L}\p{N}\s]/, " ").split.reject { |w| STOPWORDS.include?(w) || w.length < 3 }
    end

    STOPWORDS = %w[the and para por con una uno los las del que como cuando donde
                   este esta esto mis mío soy son fue por qué como está estoy
                   necesito quiero puedo hola gracias buenas].freeze

    def parse(raw)
      front, body = split_front_matter(raw)
      Article.new(
        id:        front["id"],
        title:     front["title"],
        category:  front["category"],
        sensitive: front["sensitive"].to_s == "true",
        tags:      Array(front["tags"]),
        body:      body
      )
    end

    def split_front_matter(raw)
      if raw =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
        [ parse_front_matter($1), $2 ]
      else
        [ {}, raw ]
      end
    end

    # Minimal YAML-ish parser for the flat front matter we control.
    def parse_front_matter(text)
      text.lines.each_with_object({}) do |line, acc|
        next unless line.strip =~ /\A([a-z_]+):\s*(.*)\z/

        key, value = $1, $2.strip
        acc[key] =
          if value.start_with?("[") && value.end_with?("]")
            value[1..-2].split(",").map(&:strip).reject(&:empty?)
          else
            value
          end
      end
    end
  end
end
