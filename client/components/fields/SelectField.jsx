import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import { equals } from 'ramda'

import { hasValue, createPropType } from 'helpers/validation'
import { internalRequest } from 'helpers/request'

const notSelected = { value: 0, text: 'NotSelected' }

const NameCodeOption = {
  transform: x => ({
    ...x,
    value: x.id,
    label: hasValue(x.code) ? `${x.code} ${x.name}` : x.name,
  }),
  // eslint-disable-next-line react/prop-types
  render: localize => ({ id, name, code }) => (
    <div className="content">
      <div className="title">{id === notSelected.value ? localize(name) : name}</div>
      <strong className="description">{code}</strong>
    </div>
  ),
}

// eslint-disable-next-line react/prop-types
const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => {
      onRemove(value)
    }}
    removeIcon="delete"
    color="blue"
    basic
  />
)

// eslint-disable-next-line react/prop-types
const createValueComponent = localize => ({ value: { value, label } }) => (
  <div className="Select-value">
    <span className="Select-value-label" role="option" aria-selected="true">
      {value === notSelected.value ? localize(label) : label}
    </span>
  </div>
)

const numOrStr = oneOfType([number, string])

class SelectField extends React.Component {
  static propTypes = {
    name: string.isRequired,
    value: createPropType(props => (props.multiselect ? arrayOf(numOrStr) : numOrStr)),
    setFieldValue: func.isRequired,
    onBlur: func,
    errors: arrayOf(string),
    label: string.isRequired,
    title: string,
    placeholder: string,
    multiselect: bool,
    required: bool,
    touched: bool.isRequired,
    disabled: bool,
    inline: bool,
    width: numOrStr,
    createOptionComponent: func,
    localize: func.isRequired,
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
    value: '',
    onBlur: _ => _,
    title: undefined,
    placeholder: undefined,
    multiselect: false,
    required: false,
    errors: [],
    disabled: false,
    inline: false,
    width: undefined,
    createOptionComponent: NameCodeOption.render,
    pageSize: 10,
    waitTime: 250,
    lookup: undefined,
    responseToOption: NameCodeOption.transform,
    options: undefined,
  }

  state = {
    value: hasValue(this.props.value)
      ? this.props.value
      : this.props.multiselect ? [] : notSelected.value,
    optionsFetched: false,
  }

  componentDidMount() {
    const { value: ids, lookup, multiselect, responseToOption, options } = this.props
    if (hasValue(options)) return
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (hasValue(value)) {
          this.setState({
            value: multiselect ? value.map(responseToOption) : responseToOption(value[0]),
          })
        }
      },
    })
  }

  componentWillReceiveProps(nextProps) {
    if (!equals(nextProps.value && this.state.value)) {
      this.setState({ value: nextProps.value })
    }
  }

  componentWillUnmount() {
    this.handleLoadOptions.cancel()
  }

  loadOptions = (wildcard, page, callback) => {
    const { lookup, pageSize, multiselect, required, responseToOption } = this.props
    const { optionsFetched } = this.state
    internalRequest({
      url: `/api/lookup/paginated/${lookup}`,
      queryParams: { page: page - 1, pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        let options =
          multiselect || !required || optionsFetched
            ? data
            : [{ id: notSelected.value, name: notSelected.text }, ...data]
        if (responseToOption) options = options.map(responseToOption)
        if (optionsFetched) {
          callback(null, { options })
        } else {
          this.setState({ optionsFetched: true }, () => {
            callback(null, { options })
          })
        }
      },
    })
  }

  handleLoadOptions = debounce(this.loadOptions, this.props.waitTime)

  handleAsyncSelect = (data) => {
    const { multiselect, setFieldValue, name } = this.props
    const raw = data !== null ? data : { value: notSelected.value }
    const fieldValue = multiselect ? raw.map(x => x.value) : raw.value
    if (!equals(this.state.value, fieldValue)) {
      this.setState({ value: multiselect ? raw : fieldValue }, () =>
        setFieldValue(name, fieldValue))
    }
  }

  handlePlainSelect = (_, { value }) => {
    const { setFieldValue, name } = this.props
    if (!equals(this.state.value, value)) {
      this.setState({ value }, () => setFieldValue(name, value))
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
    } = this.props
    const hasErrors = touched && hasValue(errorKeys)
    const label = localize(labelKey)
    const title = titleKey ? localize(titleKey) : label
    const placeholder = placeholderKey ? localize(placeholderKey) : label
    const hasOptions = hasValue(options)
    const [Select, ownProps] = hasOptions
      ? [
        SemanticSelect,
        {
          onChange: this.handlePlainSelect,
          error: hasErrors,
          multiple: multiselect,
          options:
              multiselect || !required
                ? options
                : [{ value: notSelected.value, text: localize(notSelected.text) }, ...options],
          required,
          title,
          inline,
          width,
        },
      ]
      : [
        ReactSelect.Async,
        {
          onChange: this.handleAsyncSelect,
          loadOptions: this.handleLoadOptions,
          valueComponent: multiselect
            ? createRemovableValueComponent(localize)
            : createValueComponent(localize),
          optionRenderer: createOptionComponent(localize),
          inputProps: { type: 'react-select', name },
          className: hasErrors ? 'react-select--error' : '',
          multi: multiselect,
          backspaceRemoves: true,
          searchable: true,
          pagination: true,
        },
      ]
    const className = `field${!hasOptions && required ? ' required' : ''}`
    return (
      <div className={className}>
        <label htmlFor={name}>{label}</label>
        <Select
          {...ownProps}
          value={this.state.value}
          onBlur={onBlur}
          name={name}
          placeholder={placeholder}
          disabled={disabled}
        />
        {hasErrors && (
          <Message title={label} list={errorKeys.map(localize)} compact={hasOptions} error />
        )}
      </div>
    )
  }
}

export default SelectField
