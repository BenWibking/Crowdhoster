class CampaignsController < ApplicationController
  layout 'layouts/checkout'
  before_filter :check_init
  before_filter :load_campaign
  before_filter :check_published
  before_filter :check_exp, :except => [:home, :checkout_confirmation]

  # The load_campaign before filter grabs the campaign object from the db
  # and makes it available to all routes

  def home
    render 'theme/views/campaign', layout: 'layouts/application'
  end

  def checkout_amount
    @reward = false
    if params.has_key?(:reward) && params[:reward].to_i != 0
      @reward = Reward.find_by_id(params[:reward])
      unless @reward && @reward.campaign_id == @campaign.id && !@reward.sold_out?
        @reward = false
        flash.now[:info] = "This reward is unavailable. Please select a different reward!"
      end
    end
  end

  def checkout_payment
    @reward = false
    if @campaign.payment_type == "fixed"
      if params.has_key?(:quantity)
        @quantity = params[:quantity].to_i
        @amount = ((@quantity * @campaign.fixed_payment_amount.to_f)*100).ceil/100.0
      else
        redirect_to checkout_amount_url(@campaign), flash: { warning: "Invalid quantity!" }
        return
      end
    elsif params.has_key?(:amount) && params[:amount].to_f >= @campaign.min_payment_amount
      @amount = ((params[:amount].to_f)*100).ceil/100.0
      @quantity = 1

      if params.has_key?(:reward) && params[:reward].to_i != 0
        begin
          @reward = Reward.find(params[:reward])
        rescue => exception
          redirect_to checkout_amount_url(@campaign), flash: { info: "This reward is unavailable. Please select a different reward!" }
          return
        end
        unless @reward && @reward.campaign_id == @campaign.id && @amount >= @reward.price && !@reward.sold_out?
          if @reward.sold_out?
            flash = { info: "This reward is unavailable. Please select a different reward!" }
          else
            flash = { warning: "Please enter a higher amount to redeem this reward!" }
          end
          redirect_to checkout_amount_url(@campaign), flash: flash and return
        end
      end

    else
      redirect_to checkout_amount_url(@campaign), flash: { info: "Please enter a higher amount!" }
      return
    end

    @fee = (@campaign.apply_processing_fee)? calculate_processing_fee(@amount * 100)/100.0 : 0
    @total = @amount + @fee

  end

  def checkout_process

    client_timestamp = params.has_key?(:client_timestamp) ? params[:client_timestamp].to_i : nil
    ct_user_id = params[:ct_user_id]
    ct_card_id = params[:ct_card_id]
    fullname = params[:fullname]
    email = params[:email]
    billing_postal_code = params[:billing_postal_code]

    #calculate amount and fee in cents
    amount = (params[:amount].to_f*100).ceil
    fee = calculate_processing_fee(amount)
    quantity = params[:quantity].to_i

    #Shipping Info
    address_one = params.has_key?(:address_one) ? params[:address_one] : ''
    address_two = params.has_key?(:address_two) ? params[:address_two] : ''
    city = params.has_key?(:city) ? params[:city] : ''
    state = params.has_key?(:state) ? params[:state] : ''
    postal_code = params.has_key?(:postal_code) ? params[:postal_code] : ''
    country = params.has_key?(:country) ? params[:country] : ''

    #Additional Info
    additional_info = params.has_key?(:additional_info) ? params[:additional_info] : ''

    @reward = false
    if params[:reward].to_i != 0
      @reward = Reward.find_by_id(params[:reward])
      unless @reward && @reward.campaign_id == @campaign.id && amount >= @reward.price && !@reward.sold_out?
        if @reward.sold_out?
          flash = { info: "This reward is unavailable. Please select a different reward!" }
        else
          flash = { warning: "Please enter a higher amount to redeem this reward!" }
        end
        redirect_to checkout_amount_url(@campaign), flash: flash and return
      end
    end

    # Apply the processing fee to the user or the admin
    if @campaign.apply_processing_fee
      user_fee_amount = fee
      admin_fee_amount = 0
    else
      user_fee_amount = 0
      admin_fee_amount = fee
    end

    # TODO: Check to make sure the amount is valid here

    # Create the payment record in our db, if there are errors, redirect the user
     payment_params = {client_timestamp: client_timestamp,
                       fullname: fullname,
                       email: email,
                       billing_postal_code: billing_postal_code,
                       quantity: quantity,
                       address_one: address_one,
                       address_two: address_two,
                       city: city,
                       state: state,
                       postal_code: postal_code,
                       country: country,
                       additional_info: additional_info}

     @payment = @campaign.payments.new(payment_params)

    if !@payment.valid?
      error_messages = @payment.errors.full_messages.join(', ')
      redirect_to checkout_amount_url(@campaign), flash: { error: error_messages } and return
    end

    # Check if there's an existing payment with the same payment_params and client_timestamp. 
    # If exists, look at the status to route accordingly. 
    if !client_timestamp.nil? && existing_payment = @campaign.payments.where(payment_params).first
      case existing_payment.status
      when nil
        flash_msg = { info: "Your payment is still being processed! If you have not received a confirmation email, please try again or contact support by emailing team@crowdhoster.com" }
      when 'error'
        flash_msg = { error: "There was an error processing your payment. Please try again or contact support by emailing team@crowdhoster.com." }
      else
        # A status other than nil or 'error' indicates success! Treat as original payment
        redirect_to checkout_confirmation_url(@campaign), :status => 303, :flash => { payment_guid: @payment.ct_payment_id } and return
      end
      redirect_to checkout_amount_url(@campaign), flash: flash_msg and return
    end

    @payment.save

    # Execute the payment via the Crowdtilt API, if it fails, redirect user
    begin
      payment = {
        amount: amount,
        user_fee_amount: user_fee_amount,
        admin_fee_amount: admin_fee_amount,
        user_id: ct_user_id,
        card_id: ct_card_id,
        metadata: {
          fullname: fullname,
          email: email,
          billing_postal_code: billing_postal_code,
          quantity: quantity,
          reward: @reward ? @reward.id : 0,
          additional_info: additional_info
        }
      }
      @campaign.production_flag ? Crowdtilt.production(@settings) : Crowdtilt.sandbox

      logger.info "CROWDTILT API REQUEST: /campaigns/#{@campaign.ct_campaign_id}/payments"
      logger.info payment

      response = Crowdtilt.post('/campaigns/' + @campaign.ct_campaign_id + '/payments', {payment: payment})

      logger.info "CROWDTILT API RESPONSE:"
      logger.info response
    rescue => exception
      @payment.update_attribute(:status, 'error')
      logger.info "ERROR WITH POST TO /payments: #{exception.message}"
      redirect_to checkout_amount_url(@campaign), flash: { error: "There was an error processing your payment. Please try again or contact support by emailing team@crowdhoster.com" } and return
    end

    # Sync payment data
    @payment.reward = @reward if @reward
    @payment.update_api_data(response['payment'])
    @payment.save

    # Sync campaign data
    @campaign.update_api_data(response['payment']['campaign'])
    @campaign.save

    # Send confirmation emails
    UserMailer.payment_confirmation(@payment, @campaign).deliver rescue 
      logger.info "ERROR WITH EMAIL RECEIPT: #{$!.message}"

    AdminMailer.payment_notification(@payment.id).deliver rescue 
      logger.info "ERROR WITH ADMIN NOTIFICATION EMAIL: #{$!.message}"

    redirect_to checkout_confirmation_url(@campaign), :status => 303, :flash => { payment_guid: @payment.ct_payment_id }

  end

  def checkout_confirmation
    @payment = Payment.where(:ct_payment_id => flash[:payment_guid]).first
    flash.keep(:payment_guid) # Preserve on refresh of this page only

    if flash[:payment_guid].nil? || !@payment
      redirect_to campaign_home_url(@campaign)
    end
  end

private

  def load_campaign
    @campaign = Campaign.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      redirect_to root_url
  end

  def check_published
    if !@campaign.published_flag
      unless user_signed_in? && current_user.admin?
        redirect_to root_url, :flash => { :info => "Campaign is no longer available" }
      end
    end
  end

  def check_exp
    if @campaign.expired?
      redirect_to campaign_home_url(@campaign), :info => { :error => "Campaign is expired!" }
    end
  end

end
