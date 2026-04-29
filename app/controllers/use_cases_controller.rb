class UseCasesController < ApplicationController
  layout "marketing"

  USE_CASES = UseCaseCatalog.all

  def index
    @use_cases = USE_CASES
  end

  def show
    @use_case = USE_CASES.find { |use_case| use_case[:slug] == params[:slug] }
    return render plain: "Use case not found", status: :not_found unless @use_case

    @related_use_cases = USE_CASES.reject { |use_case| use_case[:slug] == @use_case[:slug] }
                             .select { |use_case| use_case[:space] == @use_case[:space] }
    @related_use_cases = USE_CASES.reject { |use_case| use_case[:slug] == @use_case[:slug] }.first(3) if @related_use_cases.blank?
  end
end
