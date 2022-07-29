require "application_system_test_case"

class PairsTest < ApplicationSystemTestCase
  setup do
    @pair = pairs(:one)
  end

  test "visiting the index" do
    visit pairs_url
    assert_selector "h1", text: "Pairs"
  end

  test "should create pair" do
    visit pairs_url
    click_on "New pair"

    fill_in "Name", with: @pair.name
    click_on "Create Pair"

    assert_text "Pair was successfully created"
    click_on "Back"
  end

  test "should update Pair" do
    visit pair_url(@pair)
    click_on "Edit this pair", match: :first

    fill_in "Name", with: @pair.name
    click_on "Update Pair"

    assert_text "Pair was successfully updated"
    click_on "Back"
  end

  test "should destroy Pair" do
    visit pair_url(@pair)
    click_on "Destroy this pair", match: :first

    assert_text "Pair was successfully destroyed"
  end
end
