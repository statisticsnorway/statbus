import React from 'react'
import { arrayOf, func, number, shape, string } from 'prop-types'

import styles from './styles'

class MappingsEditor extends React.Component {

  static propTypes = {
    attributes: arrayOf(string).isRequired,
    columns: arrayOf(shape({ regId: number, name: string })).isRequired,
    value: arrayOf(shape({
      attribute: string.isRequired,
      column: string.isRequired,
    })),
    onChange: func.isRequired,
  }

  static defaultProps = {
    value: [],
  }

  state = {
    left: undefined,
    right: undefined,
  }

  getOther(prop) {
    return prop === 'left'
      ? this.state.right
      : this.state.left
  }

  handleChange(prop, value) {
    const pair = prop === 'left'
      ? [value, this.state.right]
      : [this.state.left, value]
    this.props.onChange(pair)
  }

  handleSelect = prop => value => () => {
    if (this.getOther(prop)) {
      this.setState({ left: undefined, right: undefined })
      this.handleChange(prop, value)
    } else {
      this.setState({ [prop]: value })
    }
  }

  render() {
    const { attributes, columns, value: mappings } = this.props
    return (
      <div className={styles.attributesRoot}>
        <div>
          {attributes.map(attr =>
            <span key={attr} onClick={this.handleSelect('left')(attr)}>{attr}</span>)}
        </div>
        <div>
          {columns.map(col =>
            <span key={col.regId} onClick={this.handleSelect('right')(col.name)}>{col.name}</span>)}
        </div>
      </div>
    )
  }
}

export default MappingsEditor
