import React from 'react'
import { arrayOf, string, number, oneOfType, func, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'

import Form from 'components/Form'
import { internalRequest } from 'helpers/request'

const withDefault = (options, localize) => [{ id: 0, name: localize('NotSelected') }, ...options]
const isNonNullable = x => [
  'localUnits',
  'legalUnits',
  'enterpriseUnits',
  'enterpriseUnitRegId',
  'enterpriseGroupRegId',
  'legalUnitId',
  'entGroupId',
].includes(x)

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

  handleChange = (_, { value }) => {
    const { name, onChange } = this.props
    onChange({ name, value })
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
