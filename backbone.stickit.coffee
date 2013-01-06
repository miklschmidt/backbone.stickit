(($) ->
	
	# Backbone.View Mixins
	# --------------------
	_.extend Backbone.View::,
		
		# Collection of model event bindings.
		#   [{model,event,fn}, ...]
		_modelBindings: null
		
		# Unbind the model bindings that are referenced in `this._modelBindings`. If
		# the optional `model` parameter is defined, then only delete bindings for
		# the given `model`.
		unstickModel: (model) ->
			_.each @_modelBindings, _.bind((binding, i) ->
				return false  if model and binding.model isnt model
				binding.model.off binding.event, binding.fn
				delete @_modelBindings[i]
			, this)
			@_modelBindings = _.compact(@_modelBindings)

		
		# Using `this.bindings` configuration or the `optionalBindingsConfig`, binds `this.model`
		# or the `optionalModel` to elements in the view.
		stickit: (optionalModel, optionalBindingsConfig) ->
			self = this
			model = optionalModel or @model
			bindings = optionalBindingsConfig or @bindings or {}
			props = ["autofocus", "autoplay", "async", "checked", "controls", "defer", "disabled", "hidden", "loop", "multiple", "open", "readonly", "required", "scoped", "selected"]
			@_modelBindings or (@_modelBindings = [])
			@unstickModel model
			@events or (@events = {})
			
			# Iterate through the selectors in the bindings configuration and configure
			# the various options for each field.
			_.each _.keys(bindings), (selector) ->
				$el = undefined
				options = undefined
				modelAttr = undefined
				visibleCb = undefined
				config = bindings[selector] or {}
				bindKey = _.uniqueId()
				
				# Support ':el' selector - special case selector for the view managed delegate.
				if selector is ":el"
					$el = self.$el
					selector = ""
				else
					$el = self.$(selector)
				
				# Fail fast if the selector didn't match an element.
				return false  unless $el.length
				
				# Allow shorthand setting of model attributes - `'selector':'modelAttr'`.
				config = modelAttr: config  if _.isString(config)
				
				# Keep backward-compatibility for `modelAttr` which was renamed `observe`.
				modelAttr = config.observe or config.modelAttr
				config.updateModel = true  unless config.updateModel?
				config.updateView = true  unless config.updateView?
				
				# Keep backward-compatibility for `format` which was renamed `onGet`.
				config.onGet = config.format  if config.format and not config.onGet

				# Support piping functions in onGet
				config.onGet = (pipe.trim() for pipe in config.onGet.split '|') if _.isString(config.onGet)
				
				# Support piping functions in onSet
				config.onSet = (pipe.trim() for pipe in config.onSet.split '|') if _.isString(config.onSet)


				# Create the model set options with a unique `bindKey` so that we
				# can avoid double-binding in the `change:attribute` event handler.
				options = _.extend(
					bindKey: bindKey
				, config.setOptions or {})
				
				# Setup the attributes configuration - a list that maps an attribute or
				# property `name`, to an `observe`d model attribute, using an optional
				# `onGet` formatter.
				#
				#     [{
				#       name: 'attributeOrPropertyName',
				#       observe: 'modelAttrName'
				#       onGet: function(modelAttrVal, modelAttrName) { ... }
				#     }, ...]
				#
				_.each config.attributes or [], (attrConfig) ->
					lastClass = ""
					observed = attrConfig.observe or modelAttr
					updateAttr = ->
						updateType = (if _.indexOf(props, attrConfig.name, true) > -1 then "prop" else "attr")
						val = getVal(model, observed, attrConfig, self)
						
						# If it is a class then we need to remove the last value and add the new.
						if attrConfig.name is "class"
							$el.removeClass(lastClass).addClass val
							lastClass = val
						else
							$el[updateType] attrConfig.name, val

					
					# Keep backward-compatibility for `format` which is now `onGet`.
					attrConfig.onGet = attrConfig.format  if attrConfig.format and not attrConfig.onGet

					# Support piping functions in onGet
					attrConfig.onGet = (pipe.trim() for pipe in attrConfig.onGet.split '|') if _.isString(attrConfig.onGet)
					
					# Support piping functions in onSet
					attrConfig.onSet = (pipe.trim() for pipe in attrConfig.onSet.split '|') if _.isString(attrConfig.onSet)

					_.each _.flatten([observed]), (attr) ->
						observeModelEvent model, self, "change:" + attr, updateAttr

					updateAttr()

				
				# If `visible` is configured, then the view element will be shown/hidden
				# based on the truthiness of the modelattr's value or the result of the
				# given callback. If a `visibleFn` is also supplied, then that callback
				# will be executed to manually handle showing/hiding the view element.
				if config.visible?
					visibleCb = ->
						updateVisibleBindEl $el, getVal(model, modelAttr, config, self), modelAttr, config, self

					observeModelEvent model, self, "change:" + modelAttr, visibleCb
					visibleCb()
					return false
				if modelAttr
					if isFormEl($el) or isContenteditable($el)
						
						# Bind events to the element which will update the model with changes.
						_.each config.eventsOverride or getModelEvents($el), (type) ->
							# Ugly hack that makes this work in node-webkit
							setTimeout (() ->
								# Chaplin style events
								self.delegate type, selector, () ->
									val = getElVal($el, isContenteditable($el))
									
									# Don't update the model if false is returned from the `updateModel` configuration.
									if evaluateBoolean(self, config.updateModel, val, modelAttr)
										setVal model, modelAttr, val, options, config.onSet, self
										if config.persistUpdates is yes
											model.save()
							), 1
					
					# Setup a `change:modelAttr` observer to keep the view element in sync.
					# `modelAttr` may be an array of attributes or a single string value.
					_.each _.flatten([modelAttr]), (attr) ->
						observeModelEvent model, self, "change:" + attr, (model, val, options) ->
							updateViewBindEl self, $el, config, getVal(model, modelAttr, config, self), model  if not options? or options.bindKey isnt bindKey


					updateViewBindEl self, $el, config, getVal(model, modelAttr, config, self), model, true

			
			# Wrap remove so that we can remove model events when this view is removed.
			@remove = _.wrap(@remove, (oldRemove) ->
				self.unstickModel()
				oldRemove.call self  if oldRemove
			)

	
	# Helpers
	# -------
	
	# Evaluates the given `path` (in object/dot-notation) relative to the given `obj`.
	evaluatePath = (obj, path) ->
		pathParts = (path or "").split(".")
		_.reduce(pathParts, (memo, i) ->
			memo[i]
		, obj) or obj

	
	# If the given `fn` is a string, then view[fn] is called, otherwise it is a function
	# that should be executed.
	applyViewFn = (view, fn) ->
		func = (if _.isString(fn) then view[fn] else fn)
		unless func?
			if _.isString(fn)
				console?.debug? view
				throw "Function called #{fn} doesn't exist on view logged above"
		(func).apply view, _.toArray(arguments).slice(2)  if fn

	isFormEl = ($el) ->
		_.indexOf(["CHECKBOX", "INPUT", "SELECT", "TEXTAREA"], $el[0].nodeName, true) > -1

	isCheckbox = ($el) ->
		$el.is "input[type=checkbox]"

	isRadio = ($el) ->
		$el.is "input[type=\"radio\"]"

	isNumber = ($el) ->
		$el.is "input[type=number]"

	isSelect = ($el) ->
		$el.is "select"

	isTextarea = ($el) ->
		$el.is "textarea"

	isInput = ($el) ->
		$el.is "input"

	isContenteditable = ($el) ->
		$el.attr('contenteditable')?

	
	# Given a function, string (view function reference), or a boolean
	# value, returns the truthy result. Any other types evaluate as false.
	evaluateBoolean = (view, reference) ->
		if _.isBoolean(reference)
			return reference
		else return applyViewFn.apply(this, _.toArray(arguments))  if _.isFunction(reference) or _.isString(reference)
		false

	
	# Setup a model event binding with the given function, and track the
	# event in the view's _modelBindings.
	observeModelEvent = (model, view, event, fn) ->
		
		bindModel = (model) ->
			model.on event, fn, view
			view._modelBindings.push
				model: model
				event: event
				fn: fn

		bindCollection = (collection) ->
			models = collection.models or collection
			for model in collection.models
				bindModel model

		if model instanceof Backbone.Collection

			collection = model
			bindCollection collection

			collection.on 'sync reset', bindCollection
			collection.on 'add', bindModel
			collection.on 'remove', (model) ->
				for binding, index in view._modelBindings
					if binding? and binding.model is model and binding.event is event and binding.fn is fn
						binding.model.off binding.event, binding.fn
						delete view._modelBindings[index]

			# We prolly want to get notified if items are added / delete regardless of 
			# which attributes we are tracking.
			# TODO: Garbage collection
			collection.on 'remove add', fn, view

		else
			model.on event, fn, view
			view._modelBindings.push
				model: model
				event: event
				fn: fn


	
	# Prepares the given value and sets it into the model.
	setVal = (model, attr, val, options, onSet, context) ->
		if onSet? and _.isArray(onSet)
			for formatter in onSet
				val = applyViewFn(context, formatter, val, attr)
		else if onSet?
			val = applyViewFn(context, onSet, val, attr)

		model.set attr, val, options
		console.log model,attr,val,options,context

	
	# Returns the given `field`'s value from the `model`, escaping and formatting if necessary.
	# If `field` is an array, then an array of respective values will be returned.
	getVal = (model, field, config, context) ->
		val = undefined
		retrieveVal = (attr) ->
			retrieved = (if config.escape then model.escape(attr) else model.get(attr))
			(if _.isUndefined(retrieved) then "" else retrieved)

		val = (if _.isArray(field) then _.map(field, retrieveVal) else retrieveVal(field))
		if config.onGet? and _.isArray(config.onGet)
			# Piped
			for formatter in config.onGet
				val = applyViewFn(context, formatter, val, field)
			return val
		else if config.onGet?
			# Single function
			return applyViewFn(context, config.onGet, val, field)
		else 
			# No formatter specificed
			return val

	
	# Returns the list of events needed to bind to the given form element.
	getModelEvents = ($el) ->
		
		# Binding to `oninput` is off the table since IE9- has buggy to no support, and
		# using feature detection doesn't work because it is hard to sniff in Firefox.
		if isInput($el) or isTextarea($el) or isContenteditable($el)
			["keyup", "change", "paste", "cut"]
		else
			["change"]

	
	# Gets the value from the given element, with the optional hint that the value is html.
	getElVal = ($el, isHTML) ->
		val = undefined
		if isFormEl($el)
			if isCheckbox($el)
				val = $el.prop("checked")
			else if isNumber($el)
				val = Number($el.val())
			else if isRadio($el)
				val = $el.filter(":checked").val()
			else if isSelect($el)
				if $el.prop("multiple")
					val = $el.find("option:selected").map(->
						$(this).data "stickit_bind_val"
					).get()
				else
					val = $el.find("option:selected").data("stickit_bind_val")
			else
				val = $el.val()
		else
			if isHTML
				val = $el.html()
			else
				val = $el.text()
		val

	
	# Updates the given element according to the rules for the `visible` api key.
	updateVisibleBindEl = ($el, val, attrName, config, context) ->
		visible = config.visible
		visibleFn = config.visibleFn
		isVisible = !!val
		
		# If `visible` is a function then it should return a boolean result to show/hide.
		isVisible = applyViewFn(context, visible, val, attrName)  if _.isFunction(visible) or _.isString(visible)
		
		# Either use the custom `visibleFn`, if provided, or execute a standard jQuery show/hide.
		unless visibleFn
			if isVisible
				$el.show()
			else
				$el.hide()

	
	# Update the value of `$el` in `view` using the given configuration.
	updateViewBindEl = (view, $el, config, val, model, isInitializing) ->
		modelAttr = config.observe or config.modelAttr
		afterUpdate = config.afterUpdate
		selectConfig = config.selectOptions
		updateMethod = config.updateMethod or "text"
		originalVal = getElVal($el, (config.updateMethod is "html" or isContenteditable($el)))
		
		# Don't update the view if `updateView` returns false.
		return  unless evaluateBoolean(view, config.updateView, val)
		if isRadio($el)
			$el.filter("[value=\"" + val + "\"]").prop "checked", true
		else if isCheckbox($el)
			$el.prop "checked", !!val
		else if isInput($el) or isTextarea($el)
			$el.val val
		else if isContenteditable($el)
			$el.html val
		else if isSelect($el)
			optList = undefined
			list = selectConfig.collection
			isMultiple = $el.prop("multiple")
			$el.html ""
			
			# The `list` configuration is a function that returns the options list or a string
			# which represents the path to the list relative to `window`.
			optList = (if _.isFunction(list) then applyViewFn(view, list) else evaluatePath(window, list))
			
			# Add an empty default option if the current model attribute isn't defined.
			$el.append("<option/>").find("option").prop("selected", true).data "stickit_bind_val", val  unless val?
			if _.isArray(optList)
				addSelectOptions optList, $el, selectConfig, val, isMultiple
			else
				
				# If the optList is an object, then it should be used to define an optgroup. An
				# optgroup object configuration looks like the following:
				#
				#     {
				#       'opt_labels': ['Looney Tunes', 'Three Stooges'],
				#       'Looney Tunes': [{id: 1, name: 'Bugs Bunny'}, {id: 2, name: 'Donald Duck'}],
				#       'Three Stooges': [{id: 3, name : 'moe'}, {id: 4, name : 'larry'}, {id: 5, name : 'curly'}]
				#     }
				#
				_.each optList.opt_labels, (label) ->
					$group = $("<optgroup/>").attr("label", label)
					addSelectOptions optList[label], $group, selectConfig, val, isMultiple
					$el.append $group

		else
			$el[updateMethod] val
		
		# Execute the `afterUpdate` callback from the `bindings` config.
		applyViewFn view, afterUpdate, $el, val, originalVal  unless isInitializing

	addSelectOptions = (optList, $el, selectConfig, fieldVal, isMultiple) ->
		_.each optList, (obj) ->
			option = $("<option/>")
			optionVal = obj
			
			# If the list contains a null/undefined value, then an empty option should
			# be appended in the list; otherwise, fill the option with text and value.
			if obj?
				option.text evaluatePath(obj, selectConfig.labelPath)
				optionVal = evaluatePath(obj, selectConfig.valuePath)
			else return false  if $el.find("option").length and not $el.find("option:eq(0)").data("stickit_bind_val")?
			
			# Save the option value so that we can reference it later.
			option.data "stickit_bind_val", optionVal
			
			# Determine if this option is selected.
			if not isMultiple and optionVal? and fieldVal? and optionVal is fieldVal or (_.isObject(fieldVal) and _.isEqual(optionVal, fieldVal))
				option.prop "selected", true
			else if isMultiple and _.isArray(fieldVal)
				_.each fieldVal, (val) ->
					val = evaluatePath(val, selectConfig.valuePath)  if _.isObject(val)
					option.prop "selected", true  if val is optionVal or (_.isObject(val) and _.isEqual(optionVal, val))

			$el.append option

) window.jQuery or window.Zepto