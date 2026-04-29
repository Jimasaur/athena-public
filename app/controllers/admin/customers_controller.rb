module Admin
  class CustomersController < BaseController
    def index
      @customers = Customer.order(created_at: :desc)
      @agent_settings = AgentSetting.where.not(twilio_number: [ nil, "" ]).order(:name)
      formatter = ApplicationController.helpers
      @agent_options = @agent_settings.map do |agent|
        label_name = agent.name.presence || agent.agent_id
        [ "#{label_name} · #{formatter.format_phone(agent.twilio_number)}", agent.id ]
      end
    end

    def show
      @customer = Customer.find(params[:id])
      @conversations = @customer.conversations.order(created_at: :desc)
    end

    def new
      @customer = Customer.new
    end

    def create
      @customer = Customer.new(customer_params)

      if @customer.save
        redirect_to admin_customer_path(@customer), notice: "Patient created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @customer = Customer.find(params[:id])
    end

    def update
      @customer = Customer.find(params[:id])

      if @customer.update(customer_params)
        redirect_to admin_customer_path(@customer), notice: "Patient updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      customer = Customer.find(params[:id])
      customer.destroy
      redirect_to admin_customers_path, notice: "Patient removed."
    end

    private

    def customer_params
      params.require(:customer).permit(:name, :greeting_name, :phone_number, :customer_portrait, metadata: [ :company, :plan ])
    end
  end
end
