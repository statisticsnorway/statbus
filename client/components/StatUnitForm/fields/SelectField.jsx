import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'

import Form from 'components/SchemaForm'
import { internalRequest } from 'helpers/request'

// TODO: should be configurable
const notNullableFields = ['localUnits', 'legalUnits', 'enterpriseUnits']

class SelectField extends React.Component {

  static propTypes = {
    lookup: number,
    name: string.isRequired,
    value: oneOfType([arrayOf(number), number, arrayOf(string), string]),
    labelKey: string.isRequired,
    onChange: func.isRequired,
    localize: func.isRequired,
    multiselect: bool,
    required: bool,
    errors: arrayOf(string),
  }

  static defaultProps = {
    value: '',
    lookup: '',
    multiselect: false,
    required: false,
    errors: [],
  }

  state = {
    lookup: [],
  }

  componentDidMount() {
    internalRequest({
      url: `/api/lookup/${this.props.lookup}`,
      method: 'get',
      onSuccess: (lookup) => {
        this.setState({ lookup: notNullableFields.includes(this.props.name)
          ? lookup
          : [{ id: 0, name: this.props.localize('NotSelected') }, ...lookup] })
      },
    })
  }

  handleChange = (_, { value }) => {
    const { name } = this.props
    this.props.onChange({ name, value })
  }

  render() {
    const {
      name, value, required, labelKey, localize, errors,
    } = this.props
    const options = this.state.lookup.map(x => ({ value: x.id, text: x.name }))
    const hasErrors = errors.length !== 0
    const label = localize(labelKey)
    return (
      <div className="field">
        <Form.Select
          name={name}
          onChange={this.handleChange}
          value={value}
          required={required}
          options={options}
          multiple={this.props.multiselect}
          search
          error={hasErrors}
          label={label}
        />
        <Form.Error at={name} />
        {hasErrors && <Message error title={localize(label)} list={errors.map(localize)} />}
      </div>
    )
  }
}

export default SelectField
