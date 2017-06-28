import React from 'react'
import { node, bool, string } from 'prop-types'
import guid from 'helpers/getUid'
import styles from './styles.pcss'

export default class Printable extends React.Component {

  static propTypes = {
    children: node.isRequired,
    btnShowCondition: bool,
    btnPrint: node.isRequired,
    iFrameId: string,
    printContainerId: string,
  }

  static defaultProps = {
    btnShowCondition: true,
    iFrameId: `iframe${guid()}`,
    printContainerId: `printContainer${guid()}`,
  }

  print = () => {
    const content = document.getElementById(this.props.printContainerId)
    const pri = document.getElementById(this.props.iFrameId).contentWindow
    pri.document.open()
    pri.document.write(content.innerHTML)
    pri.document.close()
    pri.focus()
    pri.print()
  }

  render() {
    const { iFrameId, printContainerId, children, btnPrint, btnShowCondition } = this.props
    return (
      <div>
        <div id={printContainerId}>{children}</div>
        <iframe id={iFrameId} className={styles.frameStyle} />
        {btnShowCondition && <a onClick={this.print}>{btnPrint}</a>}
      </div>
    )
  }
}
