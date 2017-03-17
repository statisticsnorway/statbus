import React from 'react'
import styles from './styles.pcss'

export default class Printable extends React.Component {

  static propTypes = {
    children: React.PropTypes.element.isRequired,
    btnShowCondition: React.PropTypes.bool.isRequired,
    btnPrint: React.PropTypes.element.isRequired,
  }

  static defaultProps = {
    btnShowCondition: true,
  }

  constructor(props) {
    super(props)
    this.print = this.print.bind(this)
  }

  print = () => {
    const content = document.getElementById('printContainer')
    const pri = document.getElementById('printFrame').contentWindow
    pri.document.open()
    pri.document.write(content.innerHTML)
    pri.document.close()
    pri.focus()
    pri.print()
  }

  render() {
    return (
      <div>
        <div id="printContainer">{this.props.children}</div>
        <iframe id="printFrame" className={styles.frameStyle} />
        {this.props.btnShowCondition && <a onClick={this.print}>{this.props.btnPrint}</a>}
      </div>
    )
  }
}
