class SearchPageService
  attr_reader :offset, :scope, :articles, :total, :sort, :age, :category, :page_total, :terms, :facets

  HITS_PER_PAGE = 10

  RADAR_PAGES                 = %w(Cms::RadarArticlePage).freeze
  AUSTRALIAN_PRESCRIBER_PAGES = %w(Cms::ApArticlePage Cms::ApGenericPage Cms::FeedbackPage).freeze
  NPS_PAGES                   = %w(Cms::ClinicalNewsPage Cms::ConsumerInfoCardPage Cms::CpdActivityPage Cms::GenericContentPage Cms::ProgramPage Cms::MedicinePage Cms::FeedbackPage, Cms::MediaReleasePage, Cms::CampaignPage).freeze
  ALL_PAGES                   = (RADAR_PAGES | AUSTRALIAN_PRESCRIBER_PAGES | NPS_PAGES).freeze
  # Not used
  STOPWORDS = %w(a an and are as at be but by for if in into is it no not of on or such that the their then there these they this to was will with).freeze

  def initialize(params)
    @q        = params[:q].to_s.strip
    @articles = []
    @offset   = params[:offset].to_i || 0
    @scope    = params[:scope] || params[:publication]
    @sort     = params[:sort] == 'most-recent'
    @age      = params[:age].to_i
    @category = params[:category] || 'all'
  end

  def self.obj_scope(scope)
    scope ||= 'all'

    key = "#{scope.to_s.upcase}_PAGES"
    key = key.gsub(/[^A-Z_]/, '')
    key = 'ALL_PAGES' unless SearchPageService.const_defined?(key)

    SearchPageService.const_get(key)
  end

  def query_scrivito
    #Form Query params and boost params based on classes
    form_query_and_boost_params(scope)
    @terms = derived_terms + processed_terms if @q.present?

    # Filter: Scope (NPS, AP, RADAR or ALL)
    @enumerator = Obj.where(:_obj_class, :equals, self.class.obj_scope(scope))

    # boosting the search results by title, description, subject ..
    @enumerator.and(@query, :contains, @terms.flatten.uniq, @boost).and_not(:_permalink, :equals, ['contact-us/give-feedback/thank-you']) if @terms.present?

    # hiding the private pages from search
    @enumerator.and_not(:display, :equals, 'private')

    # restrict unrelated pages in other classes
    if scope == "radar" || scope == "nps"
      @enumerator.and_not(:_permalink, :starts_with, ['australian-prescriber']) if @terms.present?
    elsif scope == "australian_prescriber"
      @enumerator.and_not(:_permalink, :equals, ['contact-us/give-feedback'])
    end

    # search by authors in ap article pages
    if scope == "australian_prescriber"
      # if scope == "australian_prescriber" && @enumerator.count == 0
      @authors = Obj.where(:_obj_class, :equals, 'Cms::Author').and(:*, :contains, @q)
      if @authors.count > 0
        author_roles = Obj.where(:_obj_class, :equals, 'Cms::AuthorRole').and(:*, :links_to, @authors.to_a).to_a
        article_pages = Obj.where(:*, :links_to, author_roles)
        @authors = article_pages
      end
    end
    @enumerator.and_not(:_obj_class, :equals, 'Cms::Author')

    # Sort By: Most Recent
    @enumerator.order(sort_by) if sort
    # Filter: Publication Date
    @enumerator.and(published_at_attribute, :is_greater_than, age.months.ago) if age > 0

    # Filter: Type
    @facets = @enumerator.facet(:type_facet, limit: 50)
    @facets << @authors.facet(:type_facet, limit: 50)
    @enumerator.and(:type_facet, :equals, category) unless category == 'all'

    # Results count
    @total = @enumerator.size + author_size || 0
    # Paginated results
    @enumerator.batch_size(HITS_PER_PAGE).offset(offset)
    @articles   = @enumerator.take(HITS_PER_PAGE) || []
    @articles << @authors.take(HITS_PER_PAGE) || [] if @authors.present?
    @page_total = @enumerator.size + author_size || 0
  end

  # Pagination "from" number
  def from
    offset + 1
  end

  def author_size
    @authors.present? ? @authors.size : 0
  end

  # Pagination "to" number
  def to
    count = offset + HITS_PER_PAGE
    [count, total].min
  end

  def results?
    @total > 0
  end

  def sort_by
    sort = {}
    sort[published_at_attribute] = :desc
    sort
  end

  def published_at_attribute
    :search_date
  end

  def article_scope?
    %w(radar australian_prescriber).include?(@scope)
  end

  private
    # Add components of hyphenated terms.
    # e.g. anti-biotics => anti, biotics, antibiotics
    def derived_terms
      match = @q.match(/(\w*-\w*)/)
      return [] unless match
      hyphenated_terms = match[1..-1]

      if hyphenated_terms.any?
        split_hyphenated_terms  = hyphenated_terms.map { |term| term.split('-') }
        joined_hyphenated_terms = hyphenated_terms.map { |term| term.delete('-') }
        processed_terms = hyphenated_terms << joined_hyphenated_terms
        processed_terms.flatten!
      end
    end

    # Exclude 1-character search terms and stopwords
    def processed_terms
      terms = @q.split(/[^a-zA-Z0-9_-]/).reject { |t| t.length <= 2 || STOPWORDS.include?(t) }.join(" ")
      result = []
      result << terms
    end

    # Defining the attributes which are to be searched
    # Adding boost to show results in priority order
    def form_query_and_boost_params(scope)
      case scope
      when "australian_prescriber", "radar"
        @query = [:title, :internal_description, :keywords, :body, :_permalink]
        @boost = { title: 10, internal_description: 5, keywords: 3 }
        return @query, @boost
      when "nps"
        @query = [:title, :brand_name, :description, :keywords, :subject, :_permalink]
        @boost = { title: 10, brand_name: 10, description: 5, subject: 3, keywords: 2 }
        return @query, @boost
      when "all"
        @query = [:title, :brand_name, :internal_description, :description, :keywords, :subject, :_permalink]
        @boost = { title: 10, brand_name: 10, internal_description: 5, description: 5, subject: 3, keywords: 2 }
        return @query, @boost
      end
    end

end