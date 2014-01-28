Crowdhoster.campaigns =

  init: ->

    _this = this

    $("#video_image").on "click", ->
      $("#player").removeClass("hidden")
      $("#player").css('display', 'block')
      $(this).hide()

    # Checkout section functions:
    if($('#checkout').length)
      $('html,body').animate({scrollTop: $('#header')[0].scrollHeight})

    $('#quantity').on "change", (e) ->
      quantity = $(this).val()
      $amount = $('#amount')
      new_amount = parseFloat($amount.attr('data-original')) * quantity
      $amount.val(new_amount)
      $('#total').html(new_amount.toFixed(2))

    $('#amount').on "keyup", (e) ->
      $(this).addClass('edited')
      $('#amount').removeClass('error')
      $('.error').hide()

    $('.reward_option.active').on "click", (e) ->
      $this = $(this)
      if(!$(e.target).hasClass('reward_edit'))
        $amount = $('#amount')
        $this.find('input').prop('checked', true)
        $('.reward_option').removeClass('selected').hide()
        $this.addClass('selected').show()
        $('.reward_edit').show()
        $('html,body').animate({scrollTop: $('#checkout').offset().top});
        if(!$amount.hasClass('edited'))
          $amount.val($this.attr('data-price'))

    $('.reward_edit').on "click", (e) ->
      e.preventDefault()
      $('.reward_edit').hide()
      $('.reward_option').removeClass('selected').show()
      $('input').prop('checked', false)
      $('#amount').removeClass('error')
      $('.error').hide()

    $('#amount_form').on "submit", (e) ->
      e.preventDefault()
      $reward = $('.reward_option.selected')
      $amount = $('#amount')
      if($reward && $amount.val().length == 0)
        $amount.val($reward.attr('data-price'))
        this.submit()
      else if($reward && (parseFloat($reward.attr('data-price')) > parseFloat($amount.val())))
        $amount.addClass('error')
        $('.error').html('Amount must be at least $' + $reward.attr('data-price') + ' to select that ' + $('#reward_select').attr('data-reference') + '.').show()
      else
        this.submit()

  submitPaymentForm: (form) ->
    $('#refresh-msg').show()
    $('#errors').hide()
    $('#errors').html('')
    $('button[type="submit"]').attr('disabled', true).html('Processing, please wait...')
    $('#card_number').removeAttr('name')
    $('#security_code').removeAttr('name')

    $form = $(form)

    cardData =
      number: $form.find('#card_number').val().replace(/\s/g, "")
      expiration_month: $form.find('#expiration_month').val()
      expiration_year: $form.find('#expiration_year').val()
      security_code: $form.find('#security_code').val()
      postal_code: $form.find('#billing_postal_code').val()

    errors = crowdtilt.card.validate(cardData)
    if !$.isEmptyObject(errors)
      $('#refresh-msg').hide()
      $.each errors, (index, value) ->
        $('#errors').append('<p>' + value + '</p>')
      $('#errors').show()
      $('.loader').hide()
      $button = $('button[type="submit"]')
      $button.attr('disabled', false).html('Confirm payment of $' + $button.attr('data-total'))
      $('#card_number').attr('name', 'card_number')
      $('#security_code').attr('name', 'security_code')
    else
      user_id = $form.find('#ct_user_id').val()
      crowdtilt.card.create(user_id, cardData, this.cardResponseHandler)


  cardResponseHandler: (response) ->
    form = document.getElementById('payment_form')
    request_id_token = response.request_id
    switch response.status
      when 201
        card_token = response.card.id
        card_input = $('<input name="ct_card_id" value="' + card_token + '" type="hidden" />');
        form.appendChild(card_input[0])
        card_input = $('<input name="ct_request_id" value="' + request_id_token + '" type="hidden" />');
        form.appendChild(card_input[0])
        $('#client_timestamp').val((new Date()).getTime())
        form.submit()
      else
        $('#refresh-msg').hide()
        $('#errors').append('<p>An error occurred. Please check your credit card details and try again.</p><br><p>If you continue to experience issues, please <a href="mailto:team@crowdhoster.com?subject=Support request for a payment issue&body=PLEASE DESCRIBE YOUR PAYMENT ISSUES HERE">click here</a> to contact support.</p>')
        $('#errors').show()
        $('.loader').hide()
        $button = $('button[type="submit"]')
        $button.attr('disabled', false).html('Confirm payment of $' + $button.attr('data-total') )
        $('#card_number').attr('name', 'card_number')
        $('#security_code').attr('name', 'security_code')
        error_path = form.getAttribute('data-error-action')
        data =
          authenticity_token: form.elements['authenticity_token'].value
          fullname: form.elements['fullname'].value
          email: form.elements['email'].value
          billing_postal_code: form.elements['billing_postal_code'].value
          ct_user_id: form.elements['ct_user_id'].value
          quantity: form.elements['quantity'].value
          amount: form.elements['amount'].value
          client_timestamp: (new Date()).getTime()
          ct_request_id: request_id_token
          ct_request_error: response.error
          ct_request_error_id: response.error_id
          # shipping fields that may or may not appear in the form
          address_one: if form.elements['address_one'] then form.elements['address_one'].value else ''
          address_two: if form.elements['address_two'] then form.elements['address_two'].value else ''
          city: if form.elements['city'] then form.elements['city'].value else ''
          state: if form.elements['state'] then form.elements['state'].value else ''
          postal_code: if form.elements['postal_code'] then form.elements['postal_code'].value else ''
          country: if form.elements['country'] then form.elements['country'].value else ''

        $.post(error_path, data)
