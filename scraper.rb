#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'
require 'wikidata_ids_decorator'

require_rel 'lib'

def scraped(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

class LegislatureTable < Scraped::HTML
  decorator RemoveFootnotes
  decorator WikidataIdsDecorator::Links
  decorator UnspanAllTables

  field :legislatures do
    rows.map { |tr| fragment(tr => LegislatureRow).to_h }
  end

  private

  def rows
    noko.xpath('//table[.//th[.="Seats"]]//tr[td]')
  end
end

class LegislatureRow < Scraped::HTML
  field :id do
    legislature_field.css('a/@wikidata').map(&:text).first
  end

  field :legislature do
    legislature_field.text.tidy
  end

  field :country do
    td.first.text.tidy
  end

  field :country_id do
    td.first.css('a/@wikidata').map(&:text).first
  end

  field :seats do
    seat_field.text.tidy
  end

  private

  def td
    noko.css('td')
  end

  def table
    noko.xpath('parent::table')
  end

  def legislature_column
    @lc ||= table.xpath('.//tr//th').find_index { |th| th.text.include? 'Name of house' }
  end

  def seat_column
    @sc ||= table.xpath('.//tr//th').find_index { |th| th.text.include? 'Seats' }
  end

  def legislature_field
    td[legislature_column]
  end

  def seat_field
    td[seat_column]
  end
end

url = 'https://en.wikipedia.org/wiki/List_of_legislatures_by_country'

page = scraped(url => LegislatureTable)
data = page.legislatures.reject { |l| l[:id].to_s.empty? || l[:seats].to_s.empty? }
data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[id], data)

__END__
# ---------- QuickStatements -------
SEAT_COUNT = 'P1342'
SOURCE = 'S854'
LLC = 'https://en.wikipedia.org/wiki/List_of_legislatures_by_country'

statements = data.map do |leg|
  data = {
    SEAT_COUNT => '"%s"' % leg[:seats][/^(\d+)/, 1],
    SOURCE => LLC,
  }
  binding.pry if data.values.any? &:nil?
  [leg[:id], data.to_a].join("\t")
end

puts statements
