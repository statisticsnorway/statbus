import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool } from 'prop-types'
import { Message, Form } from 'semantic-ui-react'

import { internalRequest } from 'helpers/request'

// TODO: should be configurable
const isNonNullable = x => ['localUnits', 'legalUnits', 'enterpriseUnits'].includes(x)
const withDefault = (options, localize) => [{ id: 0, name: localize('NotSelected') }, ...options]

class SelectField extends React.Component {

  static propTypes = {
    name: string.isRequired,
    label: string.isRequired,
    title: string,
    placeholder: string,
    value: oneOfType([arrayOf(number), number, arrayOf(string), string]),
    lookup: number,
    multiselect: bool,
    required: bool,
    touched: bool.isRequired,
    errors: arrayOf(string),
    setFieldValue: func.isRequired,
    onBlur: func,
    localize: func.isRequired,
  }

  static defaultProps = {
    value: '',
    title: undefined,
    placeholder: undefined,
    lookup: '',
    multiselect: false,
    required: false,
    errors: [],
    onBlur: _ => _,
  }

  state = {
    lookup: [],
  }

  componentDidMount() {
    internalRequest({
      url: `/api/lookup/${this.props.lookup}`,
      method: 'get',
      onSuccess: (value) => {
        const lookup = isNonNullable(this.props.name)
          ? value
          : withDefault(value, this.props.localize)
        this.setState({ lookup })
      },
    })
  }

  componentWillReceiveProps(nextProps) {
    if (!isNonNullable(nextProps.name) && this.props.localize.lang !== nextProps.localize.lang) {
      this.setState(prev => ({ lookup: withDefault(prev.lookup.slice(1), nextProps.localize) }))
    }
  }

  handleChange = (e, { value: nextValue }) => {
    const { setFieldValue, name } = this.props
    setFieldValue(name, nextValue)
  }

  render() {
    const {
      name, value, label: labelKey, title, placeholder,
      required, touched, errors,
      onBlur, localize,
    } = this.props
    const label = localize(labelKey)
    const hasErrors = touched && errors.length !== 0
    const options = this.state.lookup.map(x => ({ value: x.id, text: x.name }))
    return (
      <div className="field">
        <Form.Select
          name={name}
          label={label}
          title={title || label}
          placeholder={placeholder}
          value={value}
          options={options}
          multiple={this.props.multiselect}
          onChange={this.handleChange}
          onBlur={onBlur}
          required={required}
          error={hasErrors}
          search
        />
        {hasErrors &&
          <Message title={label} list={errors.map(localize)} error />}
      </div>
    )
  }
}

export default SelectField
