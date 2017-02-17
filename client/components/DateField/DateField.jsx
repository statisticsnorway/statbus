import React from 'react'
import DatePicker from 'react-datepicker'
import { Form } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import { getDate, toUtc } from 'helpers/dateHelper'
import styles from './styles.pcss'

class DateField extends React.Component {
  constructor(props, context) {
    super(props, context)
    this.state = {
      date: getDate(),
    }
  }

  handleChange = (date) => {
    this.setState({
      date,
    })
  }

  render() {
    const { localize, item } = this.props
    return (
      <div className={`field ${styles.datepicker}`}>
        <label>{localize(item.localizeKey)}</label>
        <DatePicker
          className="ui input"
          onChange={this.handleChange}
          selected={this.state.date}
        />
        <Form.Input
          className={styles.hidden}
          name={item.name}
          value={toUtc(this.state.date)}
        />
      </div>)
  }
}

const { func, shape, string } = React.PropTypes
DateField.propTypes = {
  localize: func.isRequired,
  item: shape({
    name: string,
    value: string,
  }).isRequired,
}

export default wrapper(DateField)
