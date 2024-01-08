import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import * as R from 'ramda'

import { hasValue, createPropType } from 'helpers/validation.js'
import { internalRequest } from 'helpers/request.js'
import { getNewName } from 'helpers/locale.js'

import styles from './styles.scss'

const notSelected = { value: undefined, text: 'NotSelected' }

const NameCodeOption = {
  transform: x => ({
    ...x,
    value: x.id,
    label: getNewName(x),
  }),
  // eslint-disable-next-line react/prop-types
  render: params => (
    <div className="content">
      <div className="title">
        {params.code && <div className={styles['select-field-code']}>{params.code}</div>}
        {params.code && <br />}
        {getNewName(params, false)}
        <hr />
      </div>
    </div>
  ),
}

// eslint-disable-next-line react/prop-types
const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => onRemove(value)}
    removeIcon="delete"
    color="blue"
    basic
  />
)

// eslint-disable-next-line react/prop-types
const createValueComponent = localize => ({ value: { value, label } }) => (
  <div className="Select-value">
    <span className="Select-value-label" role="option" aria-selected="true">
      {value === notSelected.value ? localize(notSelected.text) : label}
    </span>
  </div>
)

const numOrStr = oneOfType([number, string])

export class ForeignParticipationField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    value: createPropType(props => (props.multiselect ? arrayOf(numOrStr) : numOrStr)),
    onChange: func.isRequired,
    onBlur: func,
    errors: arrayOf(string),
    label: string,
    title: string,
    placeholder: string,
    multiselect: bool,
    required: bool,
    touched: bool,
    disabled: bool,
    inline: bool,
    width: numOrStr,
    createOptionComponent: func,
    localize: func.isRequired,
    locale: string.isRequired,
    popuplocalizedKey: string,
    pageSize: number,
    waitTime: number,
    lookup: number,
    responseToOption: func,
    options: arrayOf(shape({
      value: numOrStr.isRequired,
      text: numOrStr.isRequired,
    })),
  }

  static defaultProps = {
    value: null,
    onBlur: R.identity,
    label: null,
    title: null,
    placeholder: null,
    multiselect: false,
    required: false,
    errors: [],
    disabled: false,
    inline: false,
    width: null,
    createOptionComponent: NameCodeOption.render,
    pageSize: 10,
    waitTime: 250,
    lookup: null,
    responseToOption: NameCodeOption.transform,
    options: null,
    touched: false,
    popuplocalizedKey: null,
  }

  state = {
    initialValue: this.props.multiselect ? [] : null,
    value: hasValue(this.props.value)
      ? this.props.value
      : this.props.multiselect
        ? []
        : notSelected.value,
    optionsFetched: false,
    options: [],
    isLoading: false,
    page: 0,
    wildcard: '',
  }

  componentDidMount() {
    if (hasValue(this.props.options)) return
    const { value: ids, lookup, multiselect, responseToOption } = this.props
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (hasValue(value)) {
          this.setState({
            value: multiselect ? value.map(responseToOption) : responseToOption(value[0]),
            initialValue: multiselect ? value.map(responseToOption) : responseToOption(value[0]),
          })
        }
      },
    })
    fetch(`/api/lookup/paginated/${lookup}?page=0&pageSize=10`, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
    })
      .then(resp => resp.json())
      .then((result) => {
        const options =
          Array.isArray(result) && result.length > 0 ? result.map(responseToOption) : []
        this.setState({ options, isLoading: false, page: this.state.page + 1 })
      })
  }

  componentWillReceiveProps(nextProps) {
    const { locale, multiselect, responseToOption, isEdit } = this.props
    const { value, initialValue } = this.state
    const ids =
      isEdit && R.is(Array, nextProps.value)
        ? R.is(Array, initialValue) && initialValue.map(x => x.id)
        : initialValue && initialValue.id
    if (isEdit && R.equals(ids, nextProps.value)) {
      this.setState({ value: initialValue })
    }
    if (!R.equals(nextProps.value && value)) {
      this.setState({ value: nextProps.value })
    }
    if (nextProps.value === 0 || nextProps.value.length === 0 || nextProps.value[0] === 0) {
      this.setState({ value: '' })
    }
    if (nextProps.locale !== locale) {
      this.setState({
        value: multiselect ? value.map(responseToOption) : responseToOption(value),
        options: this.state.options.map(responseToOption),
      })
    }
  }

  componentWillUnmount() {
    this.handleLoadOptions.cancel()
  }

  loadOptions = () => {
    const { lookup, pageSize, multiselect, required, responseToOption } = this.props
    const { wildcard, page, isLoading } = this.state

    if (!isLoading) {
      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams: { page, pageSize, wildcard },
        method: 'get',
        onSuccess: (data) => {
          let options = [...data]

          if (responseToOption) options = options.map(responseToOption)
          this.setState({
            options: this.state.options.concat(options),
            page: this.state.page + 1,
          })
        },
      })
    }
  }

  handleLoadOptions = debounce(this.loadOptions, this.props.waitTime)

  handleAsyncSelect = (data) => {
    const { multiselect, onChange, responseToOption } = this.props
    const raw = data !== null ? data : { value: notSelected.value }
    const value = multiselect ? raw.map(x => x.value) : raw.value
    if (!R.equals(this.state.value, value)) {
      this.setState(
        {
          value: multiselect ? raw.map(responseToOption) : responseToOption(raw),
        },
        () => onChange(undefined, { ...this.props, value }, data),
      )
    }
  }

  handlePlainSelect = (event, { value, ...data }) => {
    const nextData = { ...data, ...this.props, value }
    if (!R.equals(this.state.value, value)) {
      this.setState({ value }, () => this.props.onChange(event, nextData))
    }
  }

  handleInputChange = (newValue) => {
    const { lookup, pageSize, responseToOption } = this.props

    if (newValue && lookup !== null) {
      this.setState({ isLoading: true })

      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams: { page: 0, pageSize, wildcard: newValue },
        method: 'get',
        onSuccess: (data) => {
          let options = [...data]

          if (responseToOption) options = options.map(responseToOption)
          this.setState({
            options,
            page: 0,
            isLoading: false,
          })
        },
      })
    }
  }

  render() {
    const {
      name,
      label: labelKey,
      touched,
      errors: errorKeys,
      options,
      multiselect,
      title: titleKey,
      placeholder: placeholderKey,
      createOptionComponent,
      required,
      disabled,
      inline,
      width,
      onBlur,
      localize,
      popuplocalizedKey,
    } = this.props
    const hasErrors = touched && hasValue(errorKeys)
    const label = labelKey !== (undefined || null) ? localize(labelKey) : undefined
    const title = titleKey ? localize(titleKey) : label
    const placeholder = placeholderKey ? localize(placeholderKey) : label
    const hasOptions = hasValue(options)
    const [Select, ownProps] = hasOptions
      ? [
        SemanticUiSelect,
        {
          onChange: this.handlePlainSelect,
          error: hasErrors,
          multiple: multiselect,
          options:
              multiselect || !required
                ? options
                : [
                  {
                    value: notSelected.value,
                    text: localize(notSelected.text),
                  },
                  ...options,
                ],
          required,
          title,
          inline,
          width,
        },
      ]
      : [
        ReactSelect,
        {
          onChange: this.handleAsyncSelect,
          loadOptions: this.loadOptions,
          valueComponent: multiselect
            ? createRemovableValueComponent(localize)
            : createValueComponent(localize),
          optionRenderer: createOptionComponent,
          inputProps: { type: 'react-select', name },
          className: hasErrors ? 'react-select--error' : '',
          multi: multiselect,
          backspaceRemoves: true,
          searchable: true,
          pagination: true,
          isLoading: this.state.isLoading,
          onMenuScrollToBottom: this.loadOptions,
          onInputChange: this.handleInputChange,
        },
      ]
    const className = `field${!hasOptions && required ? ' required' : ''}`
    return (
      <div
        className={className}
        style={{ opacity: `${disabled ? 0.25 : 1}` }}
        data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
        data-position="top left"
      >
        {label !== undefined && <label htmlFor={name}>{label}</label>}
        <Select
          {...ownProps}
          value={this.state.value}
          options={this.state.options}
          onBlur={onBlur}
          name={name}
          placeholder={placeholder}
          disabled={disabled}
          openOnFocus
        />
        {hasErrors && (
          <Message title={label} list={errorKeys.map(localize)} compact={hasOptions} error />
        )}
      </div>
    )
  }
}

export default ForeignParticipationField
